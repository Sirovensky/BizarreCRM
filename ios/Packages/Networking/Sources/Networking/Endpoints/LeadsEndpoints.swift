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
}
