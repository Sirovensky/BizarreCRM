import Foundation

/// `GET /api/v1/customers/:id` response (unwrapped envelope).
/// Server: packages/server/src/routes/customers.routes.ts:986–1069.
public struct CustomerDetail: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let firstName: String?
    public let lastName: String?
    public let title: String?
    public let email: String?
    public let phone: String?
    public let mobile: String?
    public let address1: String?
    public let address2: String?
    public let city: String?
    public let state: String?
    public let country: String?
    public let postcode: String?
    public let organization: String?
    public let contactPerson: String?
    public let customerGroupName: String?
    public let customerTags: String?
    public let comments: String?
    public let createdAt: String?
    public let updatedAt: String?

    // §44 — Health score (server-computed RFM) + LTV fields.
    // Populated by GET /api/v1/customers/:id (lines 1142–1144 in customers.routes.ts).
    // All optional; client falls back to heuristics when absent.
    public let healthScore: Int?
    public let healthLabel: String?
    public let ltvCents: Int64?
    public let lastVisitAt: String?
    public let totalSpentCents: Int64?
    public let openTicketCount: Int?
    public let complaintCount: Int?

    public let phones: [CustomerPhoneRow]?
    public let emails: [CustomerEmailRow]?

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let org = organization, !org.isEmpty { return org }
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

    public var addressLine: String? {
        let parts = [address1, address2].compactMap { $0?.isEmpty == false ? $0 : nil }
        let cityStateZip = [city, state, postcode].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
        var lines: [String] = []
        if !parts.isEmpty { lines.append(parts.joined(separator: ", ")) }
        if !cityStateZip.isEmpty { lines.append(cityStateZip) }
        if let c = country, !c.isEmpty { lines.append(c) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    public var tagList: [String] {
        guard let raw = customerTags else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public struct CustomerPhoneRow: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let phone: String
        public let label: String?
    }

    public struct CustomerEmailRow: Decodable, Sendable, Identifiable, Hashable {
        public let id: Int64
        public let email: String
        public let label: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, title, email, phone, mobile, address1, address2, city, state, country, postcode
        case organization, comments, phones, emails
        case firstName = "first_name"
        case lastName = "last_name"
        case contactPerson = "contact_person"
        case customerGroupName = "customer_group_name"
        case customerTags = "customer_tags"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // §44
        case healthScore = "health_score"
        case healthLabel = "health_label"
        case ltvCents = "ltv_cents"
        case lastVisitAt = "last_visit_at"
        case totalSpentCents = "total_spent_cents"
        case openTicketCount = "open_ticket_count"
        case complaintCount = "complaint_count"
    }
}

/// `GET /api/v1/customers/:id/analytics`.
public struct CustomerAnalytics: Decodable, Sendable, Hashable {
    public let totalTickets: Int
    public let lifetimeValue: Double
    public let avgTicketValue: Double?
    public let firstVisit: String?
    public let lastVisit: String?
    public let daysSinceLastVisit: Int?

    enum CodingKeys: String, CodingKey {
        case totalTickets = "total_tickets"
        case lifetimeValue = "lifetime_value"
        case avgTicketValue = "avg_ticket_value"
        case firstVisit = "first_visit"
        case lastVisit = "last_visit"
        case daysSinceLastVisit = "days_since_last_visit"
    }
}

/// `GET /api/v1/customers/:id/notes` — flat array.
public struct CustomerNote: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let customerId: Int64
    public let authorUserId: Int64?
    public let authorUsername: String?
    public let body: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case customerId = "customer_id"
        case authorUserId = "author_user_id"
        case authorUsername = "author_username"
        case createdAt = "created_at"
    }
}

public extension APIClient {
    func customer(id: Int64) async throws -> CustomerDetail {
        try await get("/api/v1/customers/\(id)", as: CustomerDetail.self)
    }

    func customerAnalytics(id: Int64) async throws -> CustomerAnalytics {
        try await get("/api/v1/customers/\(id)/analytics", as: CustomerAnalytics.self)
    }

    func customerRecentTickets(id: Int64, pageSize: Int = 10) async throws -> [TicketSummary] {
        let items = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        return try await get("/api/v1/customers/\(id)/tickets", query: items, as: TicketsListResponse.self).tickets
    }

    func customerNotes(id: Int64) async throws -> [CustomerNote] {
        try await get("/api/v1/customers/\(id)/notes", as: [CustomerNote].self)
    }
}
