import Foundation

/// `GET /api/v1/leads/appointments` — lives under the leads router.
/// Envelope: `{ appointments: [...], pagination: {...} }`.
public struct AppointmentsListResponse: Decodable, Sendable {
    public let appointments: [Appointment]
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

public extension APIClient {
    func listAppointments(fromDate: String? = nil, toDate: String? = nil, pageSize: Int = 100) async throws -> [Appointment] {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let f = fromDate { items.append(URLQueryItem(name: "from_date", value: f)) }
        if let t = toDate { items.append(URLQueryItem(name: "to_date", value: t)) }
        return try await get("/api/v1/leads/appointments", query: items, as: AppointmentsListResponse.self).appointments
    }
}
