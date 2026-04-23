import Foundation
import Networking

// §8 Phase 4 — Estimate create draft model

/// Persisted snapshot of in-progress estimate create form fields,
/// including line items.
public struct EstimateDraft: Codable, Sendable, Equatable {

    // MARK: - Header fields

    public var customerId: String?
    public var customerDisplayName: String?
    public var notes: String
    public var validUntil: String   // YYYY-MM-DD or empty
    public var discount: String     // decimal string, may be empty

    // MARK: - Line items

    public var lineItems: [LineItemDraft]

    // MARK: - Metadata

    public var updatedAt: Date

    public init(
        customerId: String? = nil,
        customerDisplayName: String? = nil,
        notes: String = "",
        validUntil: String = "",
        discount: String = "",
        lineItems: [LineItemDraft] = [],
        updatedAt: Date = Date()
    ) {
        self.customerId = customerId
        self.customerDisplayName = customerDisplayName
        self.notes = notes
        self.validUntil = validUntil
        self.discount = discount
        self.lineItems = lineItems
        self.updatedAt = updatedAt
    }

    // MARK: - LineItemDraft

    public struct LineItemDraft: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var description: String
        public var quantity: String   // String so TextField binds cleanly
        public var unitPrice: String
        public var taxAmount: String

        public init(
            id: UUID = UUID(),
            description: String = "",
            quantity: String = "1",
            unitPrice: String = "",
            taxAmount: String = "0"
        ) {
            self.id = id
            self.description = description
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.taxAmount = taxAmount
        }

        /// Convert to a request object, returning nil if required fields are invalid.
        public func toRequest() -> EstimateLineItemRequest? {
            guard !description.trimmingCharacters(in: .whitespaces).isEmpty,
                  let qty = Int(quantity), qty > 0,
                  let price = Double(unitPrice), price >= 0 else { return nil }
            let tax = Double(taxAmount) ?? 0
            return EstimateLineItemRequest(
                description: description.trimmingCharacters(in: .whitespaces),
                quantity: qty,
                unitPrice: price,
                taxAmount: tax
            )
        }
    }
}
