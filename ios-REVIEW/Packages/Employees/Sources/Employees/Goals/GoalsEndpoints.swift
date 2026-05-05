import Foundation
import Networking

// MARK: - Goal request/response containers

public struct GoalsListResponse: Decodable, Sendable {
    public let goals: [Goal]
}

public struct GoalResponse: Decodable, Sendable {
    public let goal: Goal
}

public struct CreateGoalRequest: Encodable, Sendable {
    public let userId: String?
    public let teamId: String?
    public let goalType: GoalType
    public let targetValue: Double
    public let period: GoalPeriod
    public let startDate: Date
    public let endDate: Date
    public let label: String?

    public init(
        userId: String?,
        teamId: String?,
        goalType: GoalType,
        targetValue: Double,
        period: GoalPeriod,
        startDate: Date,
        endDate: Date,
        label: String?
    ) {
        self.userId = userId
        self.teamId = teamId
        self.goalType = goalType
        self.targetValue = targetValue
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case teamId      = "team_id"
        case goalType    = "goal_type"
        case targetValue = "target_value"
        case period
        case startDate   = "start_date"
        case endDate     = "end_date"
        case label
    }
}

public struct UpdateGoalRequest: Encodable, Sendable {
    public let targetValue: Double?
    public let currentValue: Double?
    public let status: GoalStatus?

    public init(targetValue: Double? = nil, currentValue: Double? = nil, status: GoalStatus? = nil) {
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case targetValue  = "target_value"
        case currentValue = "current_value"
        case status
    }
}

// MARK: - APIClient extensions

public extension APIClient {
    func listGoals(userId: String? = nil, teamId: String? = nil) async throws -> [Goal] {
        var query: [URLQueryItem] = []
        if let uid = userId { query.append(.init(name: "user_id", value: uid)) }
        if let tid = teamId { query.append(.init(name: "team_id", value: tid)) }
        return try await get("/goals", query: query.isEmpty ? nil : query, as: GoalsListResponse.self).goals
    }

    func createGoal(_ req: CreateGoalRequest) async throws -> Goal {
        try await post("/goals", body: req, as: GoalResponse.self).goal
    }

    func updateGoal(id: String, _ req: UpdateGoalRequest) async throws -> Goal {
        try await patch("/goals/\(id)", body: req, as: GoalResponse.self).goal
    }

    func deleteGoal(id: String) async throws {
        try await delete("/goals/\(id)")
    }
}
