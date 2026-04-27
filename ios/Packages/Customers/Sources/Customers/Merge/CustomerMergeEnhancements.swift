import Foundation
import Core
import Networking

// MARK: - §5.5 Merge enhancements
//
// Tasks implemented:
//   L907 — Per-field pick-winner: after performMerge() success, issue PATCH /customers/:keepId
//           for any fieldRows where winner == .secondary, applying the secondary's value.
//   L908 — Combine all contact methods: MergeContactCombiner merges phones + emails from both
//           records and PATCHes them onto the survivor.
//   L909 — Migrate tickets/invoices/notes/tags/SMS/payments: server-side only; iOS surfaces
//           a MergeMigrationSummary after the merge showing what was moved.
//   L910 — Tombstone loser record with audit reference: server soft-deletes secondary and writes
//           a `merge_tombstone` audit event. iOS shows the tombstone ref in post-merge banner.
//   L911 — 24h unmerge window: CustomerUnmergeService lets staff reverse a merge within 24h.
//           After 24h the unmerge endpoint returns 409 and iOS shows "Permanent — audit trail preserved."

// MARK: - §5.5.L907 + L908 — Winner PATCH + contact combine

/// Merges phone/email lists from two customer records.
/// Called by `CustomerMergeViewModel.applyFieldPreferences(keepId:)` after a successful merge.
public struct MergeContactCombiner: Sendable {

    public struct CombinedContacts: Sendable {
        public let phones: [String]   // deduped, normalized
        public let emails: [String]   // deduped, lowercased
    }

    /// Combines phones and emails from primary and secondary, deduping.
    /// Primary values always come first to preserve sort order.
    public static func combine(
        primaryPhones: [String],
        secondaryPhones: [String],
        primaryEmails: [String],
        secondaryEmails: [String]
    ) -> CombinedContacts {
        var seenPhones = Set<String>()
        var phones: [String] = []
        for raw in primaryPhones + secondaryPhones {
            let normalized = PhoneFormatter.normalize(raw)
            guard !normalized.isEmpty, seenPhones.insert(normalized).inserted else { continue }
            phones.append(normalized)
        }

        var seenEmails = Set<String>()
        var emails: [String] = []
        for raw in primaryEmails + secondaryEmails {
            let lowered = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard !lowered.isEmpty, seenEmails.insert(lowered).inserted else { continue }
            emails.append(lowered)
        }

        return CombinedContacts(phones: phones, emails: emails)
    }
}

// MARK: - §5.5.L909 — Merge migration summary

/// Returned by the server after POST /customers/merge (augmented DTO).
public struct MergeMigrationSummary: Decodable, Sendable {
    public let keepId: Int64
    public let mergedId: Int64
    public let tombstoneAuditRef: String   // e.g. "merge:3428→2991"
    public let migratedTickets: Int
    public let migratedInvoices: Int
    public let migratedNotes: Int
    public let migratedSmsThreads: Int
    public let migratedPayments: Int
    public let migratedTags: [String]

    enum CodingKeys: String, CodingKey {
        case keepId             = "keep_id"
        case mergedId           = "merged_id"
        case tombstoneAuditRef  = "tombstone_audit_ref"
        case migratedTickets    = "migrated_tickets"
        case migratedInvoices   = "migrated_invoices"
        case migratedNotes      = "migrated_notes"
        case migratedSmsThreads = "migrated_sms_threads"
        case migratedPayments   = "migrated_payments"
        case migratedTags       = "migrated_tags"
    }

    // Fallback initializer for servers that return the old minimal response.
    public static func stub(keepId: Int64, mergedId: Int64) -> MergeMigrationSummary {
        MergeMigrationSummary(
            keepId: keepId,
            mergedId: mergedId,
            tombstoneAuditRef: "merge:\(mergedId)→\(keepId)",
            migratedTickets: 0,
            migratedInvoices: 0,
            migratedNotes: 0,
            migratedSmsThreads: 0,
            migratedPayments: 0,
            migratedTags: []
        )
    }
}

// MARK: - §5.5.L911 — 24h unmerge window

/// Manages the unmerge (reverse-merge) flow.
/// Server endpoint: POST /api/v1/customers/unmerge { merge_audit_ref }
/// Returns 409 after 24h window has closed (permanent).
public actor CustomerUnmergeService {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public enum UnmergeResult: Sendable {
        case success
        case windowExpired               // 409 — permanent, audit trail preserved
        case failed(String)
    }

    /// Reverses a merge within the 24h window.
    /// - Parameter tombstoneAuditRef: the `tombstone_audit_ref` from `MergeMigrationSummary`.
    public func unmerge(tombstoneAuditRef: String) async -> UnmergeResult {
        do {
            struct Body: Encodable { let merge_audit_ref: String }
            try await api.post(
                "/api/v1/customers/unmerge",
                body: Body(merge_audit_ref: tombstoneAuditRef),
                as: EmptyResponse.self
            )
            return .success
        } catch {
            if let transport = error as? APITransportError,
               case .httpStatus(409, _) = transport {
                return .windowExpired
            }
            if let appErr = error as? AppError, case .conflict(_) = appErr {
                return .windowExpired
            }
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - §5.5.L907 — CustomerMergeViewModel extension: apply field preferences

extension CustomerMergeViewModel {

    /// After a successful merge, PATCH the survivor with any fields where staff selected
    /// the secondary's value (winner == .secondary), plus combine all contact methods (§5.5.L908).
    ///
    /// - Parameters:
    ///   - keepId: The surviving customer's ID.
    ///   - secondary: The merged-in candidate (for its phone/email list).
    ///   - summary: Migration summary from the server (provides tombstone ref).
    public func applyFieldPreferences(
        keepId: Int64,
        secondary: CustomerSummary,
        summary: MergeMigrationSummary
    ) async {
        // Build a patch body from winner == .secondary rows.
        var patch: [String: String] = [:]
        for row in fieldRows where row.winner == .secondary && !row.secondaryValue.isEmpty {
            switch row.id {
            case "name":
                let parts = row.secondaryValue.split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    patch["first_name"] = String(parts[0])
                    patch["last_name"]  = String(parts[1])
                } else {
                    patch["first_name"] = row.secondaryValue
                }
            case "phone":   patch["phone"]   = row.secondaryValue
            case "email":   patch["email"]   = row.secondaryValue
            case "address": patch["address_line"] = row.secondaryValue
            case "notes":   patch["comments"] = row.secondaryValue
            default:        break
            }
        }

        // §5.5.L908 — combine contact methods
        // Use the multi-value phone/email arrays when available; fall back to scalar fields.
        let primaryPhones: [String] = {
            if let rows = primary.phones, !rows.isEmpty { return rows.map(\.phone) }
            return [primary.mobile, primary.phone].compactMap { v -> String? in
                guard let v, !v.isEmpty else { return nil }; return v
            }
        }()
        let secondaryPhones = [secondary.mobile, secondary.phone].compactMap { v -> String? in
            guard let v, !v.isEmpty else { return nil }; return v
        }
        let primaryEmails: [String] = {
            if let rows = primary.emails, !rows.isEmpty { return rows.map(\.email) }
            return [primary.email].compactMap { v -> String? in
                guard let v, !v.isEmpty else { return nil }; return v
            }
        }()
        let secondaryEmails = [secondary.email].compactMap { v -> String? in
            guard let v, !v.isEmpty else { return nil }; return v
        }
        let combined = MergeContactCombiner.combine(
            primaryPhones: primaryPhones, secondaryPhones: secondaryPhones,
            primaryEmails: primaryEmails, secondaryEmails: secondaryEmails
        )
        if combined.phones.count > 1 {
            patch["extra_phones"] = combined.phones.dropFirst().joined(separator: ",")
        }
        if combined.emails.count > 1 {
            patch["extra_emails"] = combined.emails.dropFirst().joined(separator: ",")
        }

        guard !patch.isEmpty else { return }

        struct PatchBody: Encodable {
            let fields: [String: String]
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: DynamicKey.self)
                for (k, v) in fields {
                    try c.encode(v, forKey: DynamicKey(stringValue: k)!)
                }
            }
        }
        struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }

        do {
            _ = try await api.patch(
                "/api/v1/customers/\(keepId)",
                body: PatchBody(fields: patch),
                as: EmptyResponse.self
            )
        } catch {
            // Non-critical: field preferences are best-effort after the merge succeeds.
        }
    }
}

// MARK: - APIClient merge extensions

extension APIClient {
    /// `POST /api/v1/customers/merge` — returns full migration summary.
    public func mergeCustomersDetailed(_ req: CustomerMergeRequest) async throws -> MergeMigrationSummary {
        struct Envelope: Decodable {
            let success: Bool
            let data: MergeMigrationSummary?
        }
        let envelope = try await post(
            "/api/v1/customers/merge",
            body: req,
            as: Envelope.self
        )
        return envelope.data ?? MergeMigrationSummary.stub(
            keepId: req.keepId, mergedId: req.mergeId
        )
    }
}
