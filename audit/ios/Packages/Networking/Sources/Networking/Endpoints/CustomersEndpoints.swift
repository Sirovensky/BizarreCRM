import Foundation

/// `GET /api/v1/customers` response.
/// Server route: packages/server/src/routes/customers.routes.ts:217–228.
/// Envelope: `{ data: { customers: [...], pagination: {...} } }`.
public struct CustomersListResponse: Decodable, Sendable {
    public let customers: [CustomerSummary]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

        enum CodingKeys: String, CodingKey {
            case page, total
            case perPage = "per_page"
            case totalPages = "total_pages"
        }
    }
}

public struct CustomerSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let organization: String?
    public let city: String?
    public let state: String?
    public let customerGroupName: String?
    public let createdAt: String?
    public let ticketCount: Int?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let org = organization, !org.isEmpty { return org }
        if let p = mobile, !p.isEmpty { return p }
        if let p = phone, !p.isEmpty { return p }
        if let e = email, !e.isEmpty { return e }
        return "Customer #\(id)"
    }

    public var initials: String {
        let first = firstName?.prefix(1).uppercased() ?? ""
        let last  = lastName?.prefix(1).uppercased() ?? ""
        let combined = first + last
        if !combined.isEmpty { return combined }
        if let org = organization?.prefix(2).uppercased(), !org.isEmpty { return String(org) }
        return "?"
    }

    public var contactLine: String? {
        if let m = mobile, !m.isEmpty { return m }
        if let p = phone, !p.isEmpty { return p }
        if let e = email, !e.isEmpty { return e }
        if let o = organization, !o.isEmpty { return o }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id, email, phone, mobile, organization, city, state
        case firstName = "first_name"
        case lastName = "last_name"
        case customerGroupName = "customer_group_name"
        case createdAt = "created_at"
        case ticketCount = "ticket_count"
    }
}

public extension APIClient {
    func listCustomers(keyword: String? = nil, pageSize: Int = 50) async throws -> CustomersListResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "pagesize", value: String(pageSize))
        ]
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        return try await get("/api/v1/customers", query: items, as: CustomersListResponse.self)
    }
}
