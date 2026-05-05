import Foundation

// §63 ext — Invoice create draft model (Phase 2)

/// Persisted snapshot of in-progress invoice create form fields.
public struct InvoiceDraft: Codable, Sendable, Equatable {
    public var customerId: String?
    public var customerDisplayName: String?
    public var ticketId: String?
    public var notes: String
    public var dueOn: String
    public var lineItems: [LineItemDraft]
    public var updatedAt: Date

    public struct LineItemDraft: Codable, Sendable, Equatable {
        public var description: String
        public var quantity: Double
        public var unitPrice: Double

        public init(description: String = "", quantity: Double = 1, unitPrice: Double = 0) {
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
        }
    }

    public init(
        customerId: String? = nil,
        customerDisplayName: String? = nil,
        ticketId: String? = nil,
        notes: String = "",
        dueOn: String = "",
        lineItems: [LineItemDraft] = [],
        updatedAt: Date = Date()
    ) {
        self.customerId = customerId
        self.customerDisplayName = customerDisplayName
        self.ticketId = ticketId
        self.notes = notes
        self.dueOn = dueOn
        self.lineItems = lineItems
        self.updatedAt = updatedAt
    }
}
