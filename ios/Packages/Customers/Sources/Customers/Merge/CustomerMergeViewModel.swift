import Foundation
import Observation
import Core
import Networking

// §5.5 Customer merge ViewModel — Phase 4 write flow.
// Drives three-step merge: pick candidate → diff fields → confirm.
//
// Server contract: POST /api/v1/customers/merge { keep_id, merge_id }
// The server always preserves the keep customer's field values and migrates
// all relational data (tickets, invoices, SMS, contacts) from merge_id → keep_id.
//
// Field preferences shown in the UI are LOCAL ONLY — they give staff a diff
// preview so they know what survives. If staff want the secondary's value for a
// field, that requires a separate PUT /customers/:id update (noted in §5.5 gap doc).

/// The side whose field value wins (used for local-only diff preview).
public enum MergeFieldWinner: String, CaseIterable, Sendable {
    case primary
    case secondary
}

/// One row in the field-diff table (local preview only — not sent to server).
public struct MergeFieldRow: Identifiable, Sendable {
    public let id: String          // field key e.g. "name"
    public let label: String
    public let primaryValue: String
    public let secondaryValue: String
    public var winner: MergeFieldWinner

    public var winnerValue: String {
        winner == .primary ? primaryValue : secondaryValue
    }
}

@MainActor
@Observable
public final class CustomerMergeViewModel {

    // MARK: - Inputs

    /// The customer whose record survives (keep).
    public let primary: CustomerDetail

    // MARK: - State

    public var candidateQuery: String = ""
    public var candidateResults: [CustomerSummary] = []
    public var selectedCandidate: CustomerSummary? = nil

    public var fieldRows: [MergeFieldRow] = []

    public private(set) var isSearching: Bool = false
    public private(set) var isMerging: Bool = false
    public private(set) var errorMessage: String? = nil
    public private(set) var conflictMessage: String? = nil
    public private(set) var mergeComplete: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    // MARK: - Init

    public init(api: APIClient, primary: CustomerDetail) {
        self.api = api
        self.primary = primary
    }

    // MARK: - Candidate search

    public func searchCandidates() async {
        let q = candidateQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { candidateResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            let response = try await api.listCustomers(keyword: q)
            // Exclude the primary from results.
            candidateResults = response.customers.filter { $0.id != primary.id }
        } catch {
            candidateResults = []
        }
    }

    public func selectCandidate(_ candidate: CustomerSummary) async {
        selectedCandidate = candidate
        await buildFieldRows(secondary: candidate)
    }

    // MARK: - Field rows

    private func buildFieldRows(secondary: CustomerSummary) async {
        let primaryName = primary.displayName
        let secondaryName = secondary.displayName

        let primaryPhone = [primary.mobile, primary.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? ""
        let secondaryPhone = [secondary.mobile, secondary.phone].compactMap { $0?.isEmpty == false ? $0 : nil }.first ?? ""

        let primaryEmail = primary.email ?? ""
        let secondaryEmail = secondary.email ?? ""

        let primaryAddress = primary.addressLine ?? ""
        let secondaryAddress = [secondary.city, secondary.state].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")

        let primaryNotes = primary.comments ?? ""

        fieldRows = [
            MergeFieldRow(id: "name",    label: "Name",    primaryValue: primaryName,    secondaryValue: secondaryName,    winner: .primary),
            MergeFieldRow(id: "phone",   label: "Phone",   primaryValue: primaryPhone,   secondaryValue: secondaryPhone,   winner: .primary),
            MergeFieldRow(id: "email",   label: "Email",   primaryValue: primaryEmail,   secondaryValue: secondaryEmail,   winner: .primary),
            MergeFieldRow(id: "address", label: "Address", primaryValue: primaryAddress, secondaryValue: secondaryAddress, winner: .primary),
            MergeFieldRow(id: "notes",   label: "Notes",   primaryValue: primaryNotes,   secondaryValue: "",               winner: .primary),
        ]
    }

    public func setWinner(_ winner: MergeFieldWinner, forRowId id: String) {
        guard let index = fieldRows.firstIndex(where: { $0.id == id }) else { return }
        fieldRows[index] = MergeFieldRow(
            id: fieldRows[index].id,
            label: fieldRows[index].label,
            primaryValue: fieldRows[index].primaryValue,
            secondaryValue: fieldRows[index].secondaryValue,
            winner: winner
        )
    }

    // MARK: - Merge

    /// Calls `POST /api/v1/customers/merge { keep_id: primary.id, merge_id: candidate.id }`.
    /// On success all relational data is migrated server-side; `mergeComplete` flips to `true`.
    public func performMerge() async {
        guard let candidate = selectedCandidate, !isMerging else { return }
        isMerging = true
        errorMessage = nil
        conflictMessage = nil
        defer { isMerging = false }

        let req = CustomerMergeRequest(
            keepId: primary.id,
            mergeId: candidate.id
        )

        do {
            _ = try await api.mergeCustomers(req)
            mergeComplete = true
        } catch {
            // HTTP 409 = conflict (e.g. open ticket on the merge candidate).
            if let transport = error as? APITransportError,
               case .httpStatus(409, let msg) = transport {
                conflictMessage = msg ?? "This customer has an open ticket — resolve it first."
            } else if let appErr = error as? AppError, case .conflict(let reason) = appErr {
                conflictMessage = reason ?? "This customer has an open ticket — resolve it first."
            } else {
                errorMessage = AppError.from(error).localizedDescription
            }
        }
    }

    // MARK: - Field preferences (local-only gap note)
    //
    // The server merge endpoint (POST /customers/merge) does not accept per-field
    // preferences; it always keeps the keep_id customer's field values and migrates
    // only relational data. The field diff shown in the UI is informational.
    //
    // Gap: if staff prefer the secondary's name/phone/email/address, they need to
    // edit the primary BEFORE merging (via PUT /customers/:id). A future enhancement
    // could automate this by issuing a PATCH after a successful merge when any
    // fieldRows have winner == .secondary. Tracked in §5.5 gap doc.
}
