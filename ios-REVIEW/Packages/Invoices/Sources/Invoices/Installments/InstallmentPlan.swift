import Foundation

// §7.9 Installment payment plans

// MARK: - InstallmentItem

/// A single scheduled payment within a plan.
public struct InstallmentItem: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// Calendar date on which payment is due.
    public let dueDate: Date
    /// Scheduled amount in cents.
    public let amountCents: Int
    /// Non-nil once the payment is confirmed by the server.
    public let paidAt: Date?

    public var isPaid: Bool { paidAt != nil }

    public init(id: Int64, dueDate: Date, amountCents: Int, paidAt: Date? = nil) {
        self.id = id
        self.dueDate = dueDate
        self.amountCents = amountCents
        self.paidAt = paidAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case dueDate    = "due_date"
        case amountCents = "amount_cents"
        case paidAt     = "paid_at"
    }
}

// MARK: - InstallmentPlan

/// A payment plan linked to a specific invoice.
/// `installments` must sum to `totalCents`; validated server-side.
public struct InstallmentPlan: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let invoiceId: Int64
    /// Full invoice total in cents (server-authoritative).
    public let totalCents: Int
    public let installments: [InstallmentItem]
    /// When true the server attempts to charge each installment automatically.
    public let autopay: Bool

    public init(
        id: Int64,
        invoiceId: Int64,
        totalCents: Int,
        installments: [InstallmentItem],
        autopay: Bool = false
    ) {
        self.id = id
        self.invoiceId = invoiceId
        self.totalCents = totalCents
        self.installments = installments
        self.autopay = autopay
    }

    /// Remaining balance (unpaid installments sum).
    public var remainingCents: Int {
        installments.filter { !$0.isPaid }.reduce(0) { $0 + $1.amountCents }
    }

    /// Next upcoming unpaid installment, sorted by due date.
    public var nextInstallment: InstallmentItem? {
        installments
            .filter { !$0.isPaid }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    enum CodingKeys: String, CodingKey {
        case id, autopay, installments
        case invoiceId   = "invoice_id"
        case totalCents  = "total_cents"
    }
}

// MARK: - DTOs

public struct CreateInstallmentPlanRequest: Encodable, Sendable {
    public struct ItemRequest: Encodable, Sendable {
        public let dueDate: String  // YYYY-MM-DD
        public let amountCents: Int

        public init(dueDate: String, amountCents: Int) {
            self.dueDate = dueDate
            self.amountCents = amountCents
        }

        enum CodingKeys: String, CodingKey {
            case amountCents = "amount_cents"
            case dueDate     = "due_date"
        }
    }

    public let invoiceId: Int64
    public let installments: [ItemRequest]
    public let autopay: Bool

    public init(invoiceId: Int64, installments: [ItemRequest], autopay: Bool = false) {
        self.invoiceId = invoiceId
        self.installments = installments
        self.autopay = autopay
    }

    enum CodingKeys: String, CodingKey {
        case installments, autopay
        case invoiceId = "invoice_id"
    }
}
