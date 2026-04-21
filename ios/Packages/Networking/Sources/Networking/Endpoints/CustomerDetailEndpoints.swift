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

// MARK: - Customer contact models (§5.6)

public struct CustomerContact: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let customerId: Int64
    public let name: String
    public let relationship: String?
    public let phone: String?
    public let email: String?
    public let isPrimary: Bool

    public init(id: Int64, customerId: Int64, name: String, relationship: String? = nil,
                phone: String? = nil, email: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.customerId = customerId
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.email = email
        self.isPrimary = isPrimary
    }

    enum CodingKeys: String, CodingKey {
        case id, name, relationship, phone, email
        case customerId = "customer_id"
        case isPrimary = "is_primary"
    }
}

public struct UpsertCustomerContactRequest: Codable, Sendable {
    public let name: String
    public let relationship: String?
    public let phone: String?
    public let email: String?
    public let isPrimary: Bool

    public init(name: String, relationship: String? = nil,
                phone: String? = nil, email: String? = nil, isPrimary: Bool = false) {
        self.name = name
        self.relationship = relationship
        self.phone = phone
        self.email = email
        self.isPrimary = isPrimary
    }

    enum CodingKeys: String, CodingKey {
        case name, relationship, phone, email
        case isPrimary = "is_primary"
    }
}

// MARK: - Customer device models (§5.7)

public struct CustomerDevice: Codable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let customerId: Int64
    public let deviceName: String
    public let imei: String?
    public let serial: String?
    public let addedAt: String?

    public init(id: Int64, customerId: Int64, deviceName: String,
                imei: String? = nil, serial: String? = nil, addedAt: String? = nil) {
        self.id = id
        self.customerId = customerId
        self.deviceName = deviceName
        self.imei = imei
        self.serial = serial
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, imei, serial
        case customerId = "customer_id"
        case deviceName = "device_name"
        case addedAt = "added_at"
    }
}

// MARK: - Customer merge models (§5.5)

public struct CustomerMergeRequest: Codable, Sendable {
    public let primaryId: Int64
    public let secondaryId: Int64
    public let fieldPreferences: CustomerMergeFieldPreferences

    public init(primaryId: Int64, secondaryId: Int64, fieldPreferences: CustomerMergeFieldPreferences) {
        self.primaryId = primaryId
        self.secondaryId = secondaryId
        self.fieldPreferences = fieldPreferences
    }

    enum CodingKeys: String, CodingKey {
        case fieldPreferences = "field_preferences"
        case primaryId = "primary_id"
        case secondaryId = "secondary_id"
    }
}

/// Per-field preference: `"primary"` or `"secondary"`.
public struct CustomerMergeFieldPreferences: Codable, Sendable {
    public var name: String
    public var phone: String
    public var email: String
    public var address: String
    public var notes: String

    public init(name: String = "primary", phone: String = "primary",
                email: String = "primary", address: String = "primary", notes: String = "primary") {
        self.name = name
        self.phone = phone
        self.email = email
        self.address = address
        self.notes = notes
    }
}

// MARK: - Tag autosuggest (§5.9)

public struct TagSuggestionsResponse: Decodable, Sendable {
    public let tags: [String]
}

public struct SetCustomerTagsRequest: Codable, Sendable {
    public let tags: [String]

    public init(tags: [String]) { self.tags = tags }
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

    // MARK: — Merge (§5.5)

    func mergeCustomers(_ req: CustomerMergeRequest) async throws -> CustomerDetail {
        try await post("/api/v1/customers/merge", body: req, as: CustomerDetail.self)
    }

    // MARK: — Contacts (§5.6)

    func customerContacts(id: Int64) async throws -> [CustomerContact] {
        try await get("/api/v1/customers/\(id)/contacts", as: [CustomerContact].self)
    }

    func createCustomerContact(customerId: Int64, _ req: UpsertCustomerContactRequest) async throws -> CustomerContact {
        try await post("/api/v1/customers/\(customerId)/contacts", body: req, as: CustomerContact.self)
    }

    func updateCustomerContact(customerId: Int64, contactId: Int64, _ req: UpsertCustomerContactRequest) async throws -> CustomerContact {
        try await patch("/api/v1/customers/\(customerId)/contacts/\(contactId)", body: req, as: CustomerContact.self)
    }

    func deleteCustomerContact(customerId: Int64, contactId: Int64) async throws {
        try await delete("/api/v1/customers/\(customerId)/contacts/\(contactId)")
    }

    // MARK: — Devices (§5.7)

    func customerDevices(id: Int64) async throws -> [CustomerDevice] {
        try await get("/api/v1/customers/\(id)/devices", as: [CustomerDevice].self)
    }

    func customerDeviceTickets(customerId: Int64, deviceId: Int64) async throws -> [TicketSummary] {
        try await get("/api/v1/customers/\(customerId)/devices/\(deviceId)/tickets", as: [TicketSummary].self)
    }

    // MARK: — Tags (§5.9)

    func setCustomerTags(id: Int64, _ req: SetCustomerTagsRequest) async throws -> CustomerDetail {
        try await post("/api/v1/customers/\(id)/tags", body: req, as: CustomerDetail.self)
    }

    func suggestCustomerTags(query: String) async throws -> [String] {
        let items = [URLQueryItem(name: "q", value: query)]
        return try await get("/api/v1/customers/tags", query: items, as: TagSuggestionsResponse.self).tags
    }
}
