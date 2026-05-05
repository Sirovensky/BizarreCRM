import Foundation

/// §40.4 — Audit trail for gift-card and store-credit operations.
///
/// Every issuance, void, reload, transfer, and redemption is recorded here.
/// The log is write-only per entry (append-only); reads drive the
/// `GiftCardAuditLogView`. Backed by `UserDefaults` as an MVP store;
/// GRDB migration with server sync deferred to Phase 5.
///
/// Actor isolation prevents concurrent mutation.
public actor GiftCardAuditLog {

    // MARK: - Singleton

    public static let shared = GiftCardAuditLog()
    private init() {}

    // MARK: - Entry type

    /// The type of gift-card operation recorded.
    public enum EntryKind: String, Codable, Sendable {
        case issued      = "issued"       // New card created
        case activated   = "activated"    // Physical card activated
        case reloaded    = "reloaded"     // Funds added
        case redeemed    = "redeemed"     // Funds used at POS
        case voided      = "voided"       // Card voided (manager PIN required)
        case transferred = "transferred"  // Balance moved to another card
        case refunded    = "refunded"     // Funds returned to card after return

        public var displayName: String {
            switch self {
            case .issued:      return "Issued"
            case .activated:   return "Activated"
            case .reloaded:    return "Reloaded"
            case .redeemed:    return "Redeemed"
            case .voided:      return "Voided"
            case .transferred: return "Transferred"
            case .refunded:    return "Refunded"
            }
        }

        /// SF Symbol for this operation kind.
        public var systemImage: String {
            switch self {
            case .issued:      return "giftcard.fill"
            case .activated:   return "checkmark.seal.fill"
            case .reloaded:    return "plus.circle.fill"
            case .redeemed:    return "dollarsign.circle.fill"
            case .voided:      return "xmark.circle.fill"
            case .transferred: return "arrow.left.arrow.right.circle.fill"
            case .refunded:    return "arrow.uturn.backward.circle.fill"
            }
        }
    }

    // MARK: - Audit entry

    public struct Entry: Codable, Identifiable, Sendable {
        public let id: UUID
        public let date: Date
        public let kind: EntryKind
        /// Last 4 digits or full code of the affected gift card.
        public let cardCode: String
        /// Amount involved in cents (positive = credit, negative = debit from card).
        public let amountCents: Int
        /// Remaining balance on card after operation, in cents. Nil if unknown.
        public let balanceCents: Int?
        /// Customer id or name involved, if known.
        public let customerReference: String?
        /// Manager who approved the operation (for voided entries). Nil when
        /// no manager approval was required.
        public let approvedByManagerId: String?
        /// Invoice / session reference for traceability.
        public let invoiceReference: String?

        public init(
            kind: EntryKind,
            cardCode: String,
            amountCents: Int,
            balanceCents: Int? = nil,
            customerReference: String? = nil,
            approvedByManagerId: String? = nil,
            invoiceReference: String? = nil
        ) {
            self.id = UUID()
            self.date = Date()
            self.kind = kind
            self.cardCode = cardCode
            self.amountCents = amountCents
            self.balanceCents = balanceCents
            self.customerReference = customerReference
            self.approvedByManagerId = approvedByManagerId
            self.invoiceReference = invoiceReference
        }
    }

    // MARK: - Storage

    private static let key     = "com.bizarrecrm.pos.giftCardAuditLog"
    private static let maxRows = 200

    // MARK: - Public API

    /// Append a new audit entry. Evicts oldest entries once limit is reached.
    public func record(_ entry: Entry) {
        var all = loadAll()
        all.append(entry)
        if all.count > Self.maxRows {
            all = Array(all.suffix(Self.maxRows))
        }
        persist(all)
    }

    /// Convenience recorder — builds and appends in one call.
    public func record(
        kind: EntryKind,
        cardCode: String,
        amountCents: Int,
        balanceCents: Int? = nil,
        customerReference: String? = nil,
        approvedByManagerId: String? = nil,
        invoiceReference: String? = nil
    ) {
        record(Entry(
            kind: kind,
            cardCode: cardCode,
            amountCents: amountCents,
            balanceCents: balanceCents,
            customerReference: customerReference,
            approvedByManagerId: approvedByManagerId,
            invoiceReference: invoiceReference
        ))
    }

    /// All entries, newest first.
    public func allNewestFirst() -> [Entry] {
        loadAll().reversed()
    }

    /// Entries for a specific card code (last 4 or full), newest first.
    public func entries(forCard code: String) -> [Entry] {
        loadAll()
            .filter { $0.cardCode.hasSuffix(code) || $0.cardCode == code }
            .reversed()
    }

    // MARK: - Internals

    private func loadAll() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
