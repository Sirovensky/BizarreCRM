import Foundation

// MARK: - ScheduledShift

public struct ScheduledShift: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let employeeId: Int64
    /// ISO-8601 UTC
    public let startAt: String
    /// ISO-8601 UTC
    public let endAt: String
    public let role: String?
    public let notes: String?
    public let published: Bool

    public init(
        id: Int64,
        employeeId: Int64,
        startAt: String,
        endAt: String,
        role: String? = nil,
        notes: String? = nil,
        published: Bool = false
    ) {
        self.id = id
        self.employeeId = employeeId
        self.startAt = startAt
        self.endAt = endAt
        self.role = role
        self.notes = notes
        self.published = published
    }

    enum CodingKeys: String, CodingKey {
        case id
        case employeeId = "employee_id"
        case startAt    = "start_at"
        case endAt      = "end_at"
        case role
        case notes
        case published
    }
}

// MARK: - CreateScheduledShiftBody

public struct CreateScheduledShiftBody: Encodable, Sendable {
    public let employeeId: Int64
    public let startAt: String
    public let endAt: String
    public let role: String?
    public let notes: String?

    public init(employeeId: Int64, startAt: String, endAt: String, role: String? = nil, notes: String? = nil) {
        self.employeeId = employeeId
        self.startAt = startAt
        self.endAt = endAt
        self.role = role
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case employeeId = "employee_id"
        case startAt    = "start_at"
        case endAt      = "end_at"
        case role
        case notes
    }
}
