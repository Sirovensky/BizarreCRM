import Foundation

/// `GET /api/v1/leads/appointments` — lives under the leads router.
/// Envelope: `{ appointments: [...], pagination: {...} }`.
public struct AppointmentsListResponse: Decodable, Sendable {
    public let appointments: [Appointment]

    public init(appointments: [Appointment]) {
        self.appointments = appointments
    }
}

public struct Appointment: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let leadId: Int64?
    public let customerId: Int64?
    public let title: String?
    public let startTime: String?
    public let endTime: String?
    public let status: String?
    public let notes: String?
    public let customerFirstName: String?
    public let customerLastName: String?
    public let assignedFirstName: String?
    public let assignedLastName: String?
    public let createdAt: String?

    public var customerName: String? {
        let parts = [customerFirstName, customerLastName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public var assignedName: String? {
        let parts = [assignedFirstName, assignedLastName]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, status, notes
        case leadId = "lead_id"
        case customerId = "customer_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case customerFirstName = "customer_first_name"
        case customerLastName = "customer_last_name"
        case assignedFirstName = "assigned_first_name"
        case assignedLastName = "assigned_last_name"
        case createdAt = "created_at"
    }
}

// MARK: - Update request (PUT /api/v1/leads/appointments/:id)

/// Mirrors the server PUT handler in `leads.routes.ts`.
/// All fields are optional — omitted keys keep the server value.
public struct UpdateAppointmentRequest: Encodable, Sendable {
    public let title: String?
    public let startTime: String?
    public let endTime: String?
    public let customerId: Int64?
    public let leadId: Int64?
    public let assignedTo: Int64?
    public let status: String?
    public let notes: String?
    public let noShow: Bool?

    public init(
        title: String? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        customerId: Int64? = nil,
        leadId: Int64? = nil,
        assignedTo: Int64? = nil,
        status: String? = nil,
        notes: String? = nil,
        noShow: Bool? = nil
    ) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.customerId = customerId
        self.leadId = leadId
        self.assignedTo = assignedTo
        self.status = status
        self.notes = notes
        self.noShow = noShow
    }

    enum CodingKeys: String, CodingKey {
        case title, status, notes
        case startTime   = "start_time"
        case endTime     = "end_time"
        case customerId  = "customer_id"
        case leadId      = "lead_id"
        case assignedTo  = "assigned_to"
        case noShow      = "no_show"
    }

    /// Custom encoder so that nil fields are omitted (sparse PUT).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = title       { try c.encode(v, forKey: .title) }
        if let v = startTime   { try c.encode(v, forKey: .startTime) }
        if let v = endTime     { try c.encode(v, forKey: .endTime) }
        if let v = customerId  { try c.encode(v, forKey: .customerId) }
        if let v = leadId      { try c.encode(v, forKey: .leadId) }
        if let v = assignedTo  { try c.encode(v, forKey: .assignedTo) }
        if let v = status      { try c.encode(v, forKey: .status) }
        if let v = notes       { try c.encode(v, forKey: .notes) }
        if let v = noShow      { try c.encode(v, forKey: .noShow) }
    }
}

// MARK: - Status strings (server-side enum)

/// Known appointment status values from the server DB schema.
public enum AppointmentStatus: String, CaseIterable, Sendable {
    case scheduled   = "scheduled"
    case confirmed   = "confirmed"
    case completed   = "completed"
    case cancelled   = "cancelled"
    case noShow      = "no-show"
}

public extension APIClient {
    func listAppointments(fromDate: String? = nil, toDate: String? = nil, pageSize: Int = 100) async throws -> [Appointment] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let f = fromDate { items.append(URLQueryItem(name: "from_date", value: f)) }
        if let t = toDate { items.append(URLQueryItem(name: "to_date", value: t)) }
        return try await get("/api/v1/leads/appointments", query: items, as: AppointmentsListResponse.self).appointments
    }

    /// PUT `/api/v1/leads/appointments/:id` — full update / reschedule.
    func updateAppointment(id: Int64, _ req: UpdateAppointmentRequest) async throws -> Appointment {
        try await put("/api/v1/leads/appointments/\(id)", body: req, as: Appointment.self)
    }

    /// DELETE `/api/v1/leads/appointments/:id` — soft-delete (cancel).
    func deleteAppointment(id: Int64) async throws {
        try await delete("/api/v1/leads/appointments/\(id)")
    }
}
