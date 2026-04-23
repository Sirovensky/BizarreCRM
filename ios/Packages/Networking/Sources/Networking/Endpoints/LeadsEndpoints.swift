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

    public init(
        id: Int64,
        orderId: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        status: String? = nil,
        leadScore: Int? = nil,
        source: String? = nil,
        assignedFirstName: String? = nil,
        assignedLastName: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.orderId = orderId
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
        self.status = status
        self.leadScore = leadScore
        self.source = source
        self.assignedFirstName = assignedFirstName
        self.assignedLastName = assignedLastName
        self.createdAt = createdAt
    }

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? (orderId ?? "Lead #\(id)") : parts.joined(separator: " ")
    }

    /// Returns a new `Lead` with `status` replaced (immutable update).
    public func withStatus(_ newStatus: String) -> Lead {
        Lead(
            id: id,
            orderId: orderId,
            firstName: firstName,
            lastName: lastName,
            email: email,
            phone: phone,
            status: newStatus,
            leadScore: leadScore,
            source: source,
            assignedFirstName: assignedFirstName,
            assignedLastName: assignedLastName,
            createdAt: createdAt
        )
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

/// `GET /api/v1/leads/{id}` — envelope-unwrapped; server returns
/// `{ success, data: { ...lead, devices, appointments, lead_score } }`.
public struct LeadDetail: Decodable, Sendable, Hashable {
    public let id: Int64
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?
    public let status: String?
    public let source: String?
    public let notes: String?
    public let leadScore: Int?
    public let assignedFirstName: String?
    public let assignedLastName: String?
    public let customerId: Int64?
    public let customerFirstName: String?
    public let customerLastName: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let devices: [LeadDevice]
    public let appointments: [LeadAppointment]

    public var displayName: String {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? "Lead #\(id)" : parts.joined(separator: " ")
    }

    public var assignedDisplayName: String? {
        let parts = [assignedFirstName, assignedLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var customerDisplayName: String? {
        let parts = [customerFirstName, customerLastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, email, phone, status, source, notes, devices, appointments
        case firstName = "first_name"
        case lastName = "last_name"
        case leadScore = "lead_score"
        case assignedFirstName = "assigned_first_name"
        case assignedLastName = "assigned_last_name"
        case customerId = "customer_id"
        case customerFirstName = "customer_first_name"
        case customerLastName = "customer_last_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct LeadDevice: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let deviceMake: String?
    public let deviceModel: String?
    public let deviceColor: String?
    public let issueDescription: String?
    public let estimatedPrice: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case deviceMake = "device_make"
        case deviceModel = "device_model"
        case deviceColor = "device_color"
        case issueDescription = "issue_description"
        case estimatedPrice = "estimated_price"
    }
}

public struct LeadAppointment: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int64
    public let startTime: String?
    public let endTime: String?
    public let title: String?
    public let location: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, title, location, status
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

// MARK: - Status update body

public struct LeadStatusUpdateBody: Encodable, Sendable {
    public let status: String
    public init(status: String) { self.status = status }
}

// MARK: - Full lead update body (PUT /leads/{id})

/// Payload for `PUT /api/v1/leads/{id}`.
/// All fields are optional; only non-nil values are encoded.
/// The server merges supplied fields over the existing row.
public struct LeadUpdateBody: Encodable, Sendable {
    public let status: String?
    public let notes: String?
    public let assignedTo: Int?
    public let source: String?
    public let lostReason: String?
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let phone: String?

    public init(
        status: String? = nil,
        notes: String? = nil,
        assignedTo: Int? = nil,
        source: String? = nil,
        lostReason: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.status = status
        self.notes = notes
        self.assignedTo = assignedTo
        self.source = source
        self.lostReason = lostReason
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.phone = phone
    }

    enum CodingKeys: String, CodingKey {
        case status, notes, source, email, phone
        case assignedTo  = "assigned_to"
        case lostReason  = "lost_reason"
        case firstName   = "first_name"
        case lastName    = "last_name"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Only encode fields the caller actually supplied (nil means "don't touch").
        if let v = status     { try c.encode(v, forKey: .status)     }
        if let v = notes      { try c.encode(v, forKey: .notes)      }
        if let v = assignedTo { try c.encode(v, forKey: .assignedTo) }
        if let v = source     { try c.encode(v, forKey: .source)     }
        if let v = lostReason { try c.encode(v, forKey: .lostReason) }
        if let v = firstName  { try c.encode(v, forKey: .firstName)  }
        if let v = lastName   { try c.encode(v, forKey: .lastName)   }
        if let v = email      { try c.encode(v, forKey: .email)      }
        if let v = phone      { try c.encode(v, forKey: .phone)      }
    }
}

// MARK: - Convert body + response

public struct LeadConvertBody: Encodable, Sendable {
    public let createTicket: Bool
    public init(createTicket: Bool = false) { self.createTicket = createTicket }
    enum CodingKeys: String, CodingKey { case createTicket = "create_ticket" }
}

/// Minimal ticket summary returned inside the convert response data.
public struct ConvertedTicket: Decodable, Sendable {
    public let id: Int64
    public let orderId: String?
    public let customerId: Int64?
    enum CodingKeys: String, CodingKey {
        case id
        case orderId    = "order_id"
        case customerId = "customer_id"
    }
}

/// `POST /api/v1/leads/{id}/convert` response data.
/// Server returns `{ ticket: {...}, message: "Lead converted to ticket" }`.
public struct LeadConvertResponse: Decodable, Sendable {
    public let ticket: ConvertedTicket
    public let message: String?
    /// Convenience accessor so call-sites can reach the new ticket ID without
    /// two levels of indirection.
    public var ticketId: Int64 { ticket.id }
    /// Customer ID threaded through from the ticket row.
    public var customerId: Int64? { ticket.customerId }
}

// MARK: - Lose body

public struct LeadLoseBody: Encodable, Sendable {
    public let reason: String
    public let notes: String
    public init(reason: String, notes: String = "") {
        self.reason = reason
        self.notes = notes
    }
}

public struct LeadLoseResponse: Decodable, Sendable {
    public let success: Bool
}

// MARK: - Follow-up body + response

public struct LeadFollowUpBody: Encodable, Sendable {
    public let dueAt: String   // ISO-8601
    public let note: String
    public init(dueAt: String, note: String) {
        self.dueAt = dueAt
        self.note = note
    }
    enum CodingKeys: String, CodingKey {
        case dueAt = "due_at"
        case note
    }
}

public struct LeadFollowUpResponse: Decodable, Sendable {
    public let id: Int64
    public let leadId: Int64
    public let dueAt: String
    public let note: String
    public let completed: Bool
    enum CodingKeys: String, CodingKey {
        case id
        case leadId    = "lead_id"
        case dueAt     = "due_at"
        case note
        case completed
    }
}

public extension APIClient {
    func listLeads(keyword: String? = nil, status: String? = nil, pageSize: Int = 50) async throws -> [Lead] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let s = status { items.append(URLQueryItem(name: "status", value: s)) }
        return try await get("/api/v1/leads", query: items, as: LeadsListResponse.self).leads
    }

    /// `GET /api/v1/leads/{id}` → full detail with devices + appointments.
    func getLead(id: Int64) async throws -> LeadDetail {
        try await get("/api/v1/leads/\(id)", as: LeadDetail.self)
    }

    /// `PUT /api/v1/leads/{id}` → update status (pipeline drag-drop).
    @discardableResult
    func updateLeadStatus(id: Int64, body: LeadStatusUpdateBody) async throws -> LeadDetail {
        try await put("/api/v1/leads/\(id)", body: body, as: LeadDetail.self)
    }

    /// `PUT /api/v1/leads/{id}` — full field update (status, notes, assignee, source, lost reason).
    @discardableResult
    func updateLead(id: Int64, body: LeadUpdateBody) async throws -> LeadDetail {
        try await put("/api/v1/leads/\(id)", body: body, as: LeadDetail.self)
    }

    /// `POST /api/v1/leads/{id}/convert` → creates ticket from lead.
    func convertLead(id: Int64, body: LeadConvertBody) async throws -> LeadConvertResponse {
        try await post("/api/v1/leads/\(id)/convert", body: body, as: LeadConvertResponse.self)
    }

    /// `POST /api/v1/leads/{id}/lose` → mark lost with reason.
    func loseLead(id: Int64, body: LeadLoseBody) async throws -> LeadLoseResponse {
        try await post("/api/v1/leads/\(id)/lose", body: body, as: LeadLoseResponse.self)
    }

    /// `POST /api/v1/leads/{id}/followup` → schedule a follow-up reminder.
    func createFollowUp(leadId: Int64, body: LeadFollowUpBody) async throws -> LeadFollowUpResponse {
        try await post("/api/v1/leads/\(leadId)/followup", body: body, as: LeadFollowUpResponse.self)
    }

    /// `GET /api/v1/leads/followups/today` → today's due reminders.
    func todayFollowUps() async throws -> [LeadFollowUpResponse] {
        try await get("/api/v1/leads/followups/today", as: [LeadFollowUpResponse].self)
    }
}
