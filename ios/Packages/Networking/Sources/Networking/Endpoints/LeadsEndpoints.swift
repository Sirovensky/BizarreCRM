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

// MARK: - Convert body + response

public struct LeadConvertBody: Encodable, Sendable {
    public let createTicket: Bool
    public init(createTicket: Bool = false) { self.createTicket = createTicket }
    enum CodingKeys: String, CodingKey { case createTicket = "create_ticket" }
}

public struct LeadConvertResponse: Decodable, Sendable {
    public let customerId: Int64
    public let ticketId: Int64?
    enum CodingKeys: String, CodingKey {
        case customerId = "customer_id"
        case ticketId   = "ticket_id"
    }
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

    /// `POST /api/v1/leads/{id}/convert` → creates customer (+ optional ticket).
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
