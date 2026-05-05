import Foundation

// MARK: - PerDiemClaim

public struct PerDiemClaim: Codable, Sendable, Identifiable, Equatable {
    public let id: Int64
    public let employeeId: Int64
    public let startDate: String    // ISO-8601
    public let endDate: String      // ISO-8601
    public let ratePerDayCents: Int
    public let totalCents: Int
    public let notes: String?
    public let status: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case employeeId      = "employee_id"
        case startDate       = "start_date"
        case endDate         = "end_date"
        case ratePerDayCents = "rate_per_day_cents"
        case totalCents      = "total_cents"
        case notes
        case status
        case createdAt       = "created_at"
    }

    public init(
        id: Int64,
        employeeId: Int64,
        startDate: String,
        endDate: String,
        ratePerDayCents: Int,
        totalCents: Int,
        notes: String? = nil,
        status: String? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.employeeId = employeeId
        self.startDate = startDate
        self.endDate = endDate
        self.ratePerDayCents = ratePerDayCents
        self.totalCents = totalCents
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - CreatePerDiemClaimBody

public struct CreatePerDiemClaimBody: Encodable, Sendable {
    public let employeeId: Int64
    public let startDate: String
    public let endDate: String
    public let ratePerDayCents: Int
    public let totalCents: Int
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case employeeId      = "employee_id"
        case startDate       = "start_date"
        case endDate         = "end_date"
        case ratePerDayCents = "rate_per_day_cents"
        case totalCents      = "total_cents"
        case notes
    }

    public init(
        employeeId: Int64,
        startDate: String,
        endDate: String,
        ratePerDayCents: Int,
        totalCents: Int,
        notes: String?
    ) {
        self.employeeId = employeeId
        self.startDate = startDate
        self.endDate = endDate
        self.ratePerDayCents = ratePerDayCents
        self.totalCents = totalCents
        self.notes = notes
    }
}
