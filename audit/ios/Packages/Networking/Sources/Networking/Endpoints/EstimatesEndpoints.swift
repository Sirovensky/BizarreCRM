import Foundation

/// `GET /api/v1/estimates` — wrapped: `{ estimates: [...], pagination: {...} }`.
public struct EstimatesListResponse: Decodable, Sendable {
    public let estimates: [Estimate]
}

// MARK: - EstimateLineItem

/// A single line item on an estimate (returned in GET /:id detail).
public struct EstimateLineItem: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let estimateId: Int64?
    public let inventoryItemId: Int64?
    public let description: String?
    public let quantity: Int?
    public let unitPrice: Double?
    public let taxAmount: Double?
    public let total: Double?
    public let itemName: String?
    public let itemSku: String?

    enum CodingKeys: String, CodingKey {
        case id, description, quantity, total
        case estimateId = "estimate_id"
        case inventoryItemId = "inventory_item_id"
        case unitPrice = "unit_price"
        case taxAmount = "tax_amount"
        case itemName = "item_name"
        case itemSku = "item_sku"
    }
}

// MARK: - Estimate

public struct Estimate: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let customerFirstName: String?
    public let customerLastName: String?
    public let customerEmail: String?
    public let customerPhone: String?
    public let status: String?
    public let subtotal: Double?
    public let discount: Double?
    public let rejectionReason: String?
    public let totalTax: Double?
    public let total: Double?
    public let validUntil: String?
    public let notes: String?
    public let createdAt: String?
    public let sentAt: String?
    public let isExpiring: Bool?
    public let daysUntilExpiry: Int?
    /// Current version number (§8.2 versioning).
    public let versionNumber: Int?
    /// Version number that the customer approved, if any.
    /// Used to detect the "customer approved v2 but staff edited to v3" scenario (§8).
    public let approvedVersionNumber: Int?
    /// Populated when fetching detail (`GET /estimates/:id`).
    public let lineItems: [EstimateLineItem]?

    public var customerName: String {
        let parts = [customerFirstName, customerLastName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, status, total, subtotal, discount, notes
        case orderId = "order_id"
        case customerId = "customer_id"
        case customerFirstName = "customer_first_name"
        case customerLastName = "customer_last_name"
        case customerEmail = "customer_email"
        case customerPhone = "customer_phone"
        case rejectionReason = "rejection_reason"
        case totalTax = "total_tax"
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case sentAt = "sent_at"
        case isExpiring = "is_expiring"
        case daysUntilExpiry = "days_until_expiry"
        case versionNumber = "version_number"
        case approvedVersionNumber = "approved_version_number"
        case lineItems = "line_items"
    }
}

public extension APIClient {
    func listEstimates(keyword: String? = nil, status: String? = nil, pageSize: Int = 50) async throws -> [Estimate] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let s = status { items.append(URLQueryItem(name: "status", value: s)) }
        return try await get("/api/v1/estimates", query: items, as: EstimatesListResponse.self).estimates
    }

    /// `GET /api/v1/estimates/:id` — full detail including line_items.
    func getEstimate(id: Int64) async throws -> Estimate {
        try await get("/api/v1/estimates/\(id)", as: Estimate.self)
    }
}
