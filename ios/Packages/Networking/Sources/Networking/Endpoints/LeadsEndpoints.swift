import Foundation

/// `GET /api/v1/leads` — wrapped: `{ leads: [...], pagination: {...} }`.
public struct LeadsListResponse: Decodable, Sendable {
    public let leads: [Lead]
}

public struct Lead: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let orderId: String?
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let status: String?
    public let leadScore: Int?
    public let source: String?
    public let assignedFirstName: String?
    public let assignedLastName: String?
    public let createdAt: String?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (orderId ?? "Lead #\(id)") : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, email, phone, status, source
        case orderId = "order_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case leadScore = "lead_score"
        case assignedFirstName = "assigned_first_name"
        case assignedLastName = "assigned_last_name"
        case createdAt = "created_at"
    }
}

public extension APIClient {
    func listLeads(keyword: String? = nil, status: String? = nil, pageSize: Int = 50) async throws -> [Lead] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let s = status { items.append(URLQueryItem(name: "status", value: s)) }
        return try await get("/api/v1/leads", query: items, as: LeadsListResponse.self).leads
    }
}
