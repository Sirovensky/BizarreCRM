import Foundation

// §7.11 Invoice Templates — saved recurring line-items

// MARK: - TemplateLineItem

public struct TemplateLineItem: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    /// Unit price in cents.
    public let unitPriceCents: Int
    public let quantity: Double
    public let taxable: Bool
    public let notes: String?

    public var totalCents: Int { Int((Double(unitPriceCents) * quantity).rounded()) }

    public init(
        id: Int64,
        name: String,
        unitPriceCents: Int,
        quantity: Double = 1.0,
        taxable: Bool = false,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.unitPriceCents = unitPriceCents
        self.quantity = quantity
        self.taxable = taxable
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, taxable, notes
        case unitPriceCents = "unit_price_cents"
    }
}

// MARK: - InvoiceTemplate

/// A saved invoice template that pre-fills line items at invoice-create time.
public struct InvoiceTemplate: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let lineItems: [TemplateLineItem]
    public let notes: String?
    public let createdAt: String?

    public init(
        id: Int64,
        name: String,
        lineItems: [TemplateLineItem],
        notes: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.name = name
        self.lineItems = lineItems
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Total value of all line items in cents.
    public var totalCents: Int { lineItems.reduce(0) { $0 + $1.totalCents } }

    enum CodingKeys: String, CodingKey {
        case id, name, notes
        case lineItems  = "line_items"
        case createdAt  = "created_at"
    }
}

// MARK: - Create/Update DTOs

public struct TemplateLineItemRequest: Encodable, Sendable {
    public let name: String
    public let unitPriceCents: Int
    public let quantity: Double
    public let taxable: Bool
    public let notes: String?

    public init(
        name: String,
        unitPriceCents: Int,
        quantity: Double = 1.0,
        taxable: Bool = false,
        notes: String? = nil
    ) {
        self.name = name
        self.unitPriceCents = unitPriceCents
        self.quantity = quantity
        self.taxable = taxable
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case name, quantity, taxable, notes
        case unitPriceCents = "unit_price_cents"
    }
}

public struct CreateInvoiceTemplateRequest: Encodable, Sendable {
    public let name: String
    public let lineItems: [TemplateLineItemRequest]
    public let notes: String?

    public init(name: String, lineItems: [TemplateLineItemRequest], notes: String? = nil) {
        self.name = name
        self.lineItems = lineItems
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case name, notes
        case lineItems = "line_items"
    }
}
