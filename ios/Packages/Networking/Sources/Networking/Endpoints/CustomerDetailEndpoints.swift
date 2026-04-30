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

    /// True when the customer has opted out of SMS marketing (server field `sms_opt_out`).
    /// Displayed as a read-only badge in the detail view; edit via the edit form.
    public let smsOptOut: Bool?

    /// Structured tags with optional server-supplied hex accent color.
    /// Populated by GET /customers/:id when the tenant has a tag-color palette configured.
    /// Falls back to `customerTags` comma-string when absent.
    public let tagItems: [CustomerTagItem]?

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
        // Prefer structured tag items when available; fall back to comma-string.
        if let items = tagItems, !items.isEmpty { return items.map(\.name) }
        guard let raw = customerTags else { return [] }
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public struct CustomerTagItem: Decodable, Sendable, Hashable {
        public let name: String
        /// 6-digit RGB hex string from server, e.g. `"FF8C00"` (no leading `#`).
        /// Nil when the tenant has not assigned a color to this tag.
        public let color: String?

        public init(name: String, color: String? = nil) {
            self.name = name
            self.color = color
        }
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
        case tagItems = "tag_items"
        // §44
        case healthScore = "health_score"
        case healthLabel = "health_label"
        case ltvCents = "ltv_cents"
        case lastVisitAt = "last_visit_at"
        case totalSpentCents = "total_spent_cents"
        case openTicketCount = "open_ticket_count"
        case complaintCount = "complaint_count"
        case smsOptOut = "sms_opt_out"
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
//
// Server contract (customers.routes.ts POST /merge):
//   Body: { keep_id: number, merge_id: number }
//   keep_id  — the surviving customer record (primary)
//   merge_id — the record that gets soft-deleted; all its tickets/invoices/SMS/contacts
//              are reassigned to keep_id by the server.
//
// Field preferences (name/phone/email/address/notes winner) are handled
// locally: the UI lets staff pick which values they want, then if they prefer
// the secondary's value they must update the customer record via PUT /customers/:id
// BEFORE or AFTER the merge. The merge endpoint itself always preserves keep_id's
// field values and only migrates relational data.

public struct CustomerMergeRequest: Codable, Sendable {
    /// The customer whose record survives (keep).  Maps to `keep_id` in the server body.
    public let keepId: Int64
    /// The customer whose record is soft-deleted.  Maps to `merge_id` in the server body.
    public let mergeId: Int64

    public init(keepId: Int64, mergeId: Int64) {
        self.keepId = keepId
        self.mergeId = mergeId
    }

    enum CodingKeys: String, CodingKey {
        case keepId = "keep_id"
        case mergeId = "merge_id"
    }
}

// NOTE: CustomerMergeFieldPreferences (local-only, UI layer) lives in the
// Customers package (Merge/CustomerMergeViewModel.swift) as MergeFieldWinner
// so it does not create a Networking→Customers dependency cycle.
// The server merge endpoint does not accept per-field preferences.

// MARK: - Invoice summary (§5.2 Invoices tab)

/// Minimal invoice row for the customer detail Invoices tab.
/// Full invoice detail lives in the Invoices package.
public struct CustomerInvoiceSummary: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let invoiceNumber: String?
    public let status: String?
    public let totalCents: Int?
    public let issuedAt: String?
    public let paidAt: String?

    public init(id: Int64, invoiceNumber: String? = nil, status: String? = nil,
                totalCents: Int? = nil, issuedAt: String? = nil, paidAt: String? = nil) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.status = status
        self.totalCents = totalCents
        self.issuedAt = issuedAt
        self.paidAt = paidAt
    }

    enum CodingKeys: String, CodingKey {
        case id, status
        case invoiceNumber = "invoice_number"
        case totalCents = "total_cents"
        case issuedAt = "issued_at"
        case paidAt = "paid_at"
    }
}

// MARK: - Communications entry (§5.2 Communications tab)

/// Unified communications timeline row (SMS / email / call log).
/// `GET /api/v1/customers/:id/communications`
public struct CustomerCommEntry: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    /// "sms" | "email" | "call"
    public let kind: String
    /// Message body / subject / call notes.
    public let body: String?
    /// Direction: "inbound" | "outbound"
    public let direction: String?
    public let createdAt: String?

    public init(id: Int64, kind: String, body: String? = nil,
                direction: String? = nil, createdAt: String? = nil) {
        self.id = id
        self.kind = kind
        self.body = body
        self.direction = direction
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, body, direction
        case createdAt = "created_at"
    }
}

// MARK: - Store credit balance (§5.2 Balance/credit)

public struct CustomerCreditBalance: Decodable, Sendable {
    public let customerId: Int64
    public let balanceCents: Int
    public let expiresAt: String?

    public init(customerId: Int64, balanceCents: Int, expiresAt: String? = nil) {
        self.customerId = customerId
        self.balanceCents = balanceCents
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case balanceCents = "balance_cents"
        case expiresAt = "expires_at"
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

    /// `GET /api/v1/customers/:id/invoices` — recent invoices for the customer detail card.
    func customerRecentInvoices(id: Int64, pageSize: Int = 5) async throws -> [InvoiceSummary] {
        let items = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        return try await get("/api/v1/customers/\(id)/invoices", query: items, as: InvoicesListResponse.self).invoices
    }

    // MARK: — Merge (§5.5)

    /// `POST /api/v1/customers/merge` — body `{ keep_id, merge_id }`.
    /// Server moves all tickets, invoices, SMS, contacts from merge_id → keep_id,
    /// then soft-deletes merge_id.  Returns the updated keep customer.
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

    // MARK: — Invoices tab (§5.2)

    /// `GET /api/v1/customers/:id/invoices` — invoice list for the customer detail Invoices tab.
    func customerInvoices(id: Int64, pageSize: Int = 50) async throws -> [CustomerInvoiceSummary] {
        let items = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        return try await get("/api/v1/customers/\(id)/invoices", query: items, as: [CustomerInvoiceSummary].self)
    }

    // MARK: — Communications tab (§5.2)

    /// `GET /api/v1/customers/:id/communications` — unified SMS/email/call timeline.
    func customerCommunications(id: Int64, pageSize: Int = 50) async throws -> [CustomerCommEntry] {
        let items = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        return try await get("/api/v1/customers/\(id)/communications", query: items, as: [CustomerCommEntry].self)
    }

    // MARK: — Store credit / balance (§5.2)

    /// `GET /api/v1/refunds/credits/:customerId` — store credit balance for this customer.
    func customerCreditBalance(customerId: Int64) async throws -> CustomerCreditBalance {
        try await get("/api/v1/refunds/credits/\(customerId)", as: CustomerCreditBalance.self)
    }

    // MARK: — Customer portal magic-link (§7.2+ / §53)

    /// `GET /api/v1/customers/:id/portal-link` — generate a single-use login URL for the
    /// customer self-service portal.  Moved here from Customers package so InvoiceDetailView
    /// can call it without a cross-package dependency on Customers.
    public func customerPortalLink(customerId: Int64) async throws -> CustomerPortalLinkResponse {
        try await get("/api/v1/customers/\(customerId)/portal-link", as: CustomerPortalLinkResponse.self)
    }
}

// MARK: - CustomerPortalLinkResponse

/// Response DTO for `GET /api/v1/customers/:id/portal-link`.
public struct CustomerPortalLinkResponse: Decodable, Sendable {
    /// Fully-qualified URL the customer can open to log into the self-service portal.
    public let url: String
    /// ISO-8601 expiry; typically 24 h from generation.
    public let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
    }
}
