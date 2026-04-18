import Foundation

/// `GET /api/v1/estimates` — wrapped: `{ estimates: [...], pagination: {...} }`.
public struct EstimatesListResponse: Decodable, Sendable {
    public let estimates: [Estimate]
}

public struct Estimate: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    public let customerFirstName: String?
    public let customerLastName: String?
    public let customerEmail: String?
    public let customerPhone: String?
    public let status: String?
    public let total: Double?
    public let validUntil: String?
    public let createdAt: String?
    public let isExpiring: Bool?
    public let daysUntilExpiry: Int?

    public var customerName: String {
        let parts = [customerFirstName, customerLastName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "—" : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, status, total
        case orderId = "order_id"
        case customerId = "customer_id"
        case customerFirstName = "customer_first_name"
        case customerLastName = "customer_last_name"
        case customerEmail = "customer_email"
        case customerPhone = "customer_phone"
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case isExpiring = "is_expiring"
        case daysUntilExpiry = "days_until_expiry"
    }
}

public extension APIClient {
    func listEstimates(keyword: String? = nil, status: String? = nil, pageSize: Int = 50) async throws -> [Estimate] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let s = status { items.append(URLQueryItem(name: "status", value: s)) }
        return try await get("/api/v1/estimates", query: items, as: EstimatesListResponse.self).estimates
    }
}
