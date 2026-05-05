import Foundation

// MARK: - GoalType

public enum GoalType: String, Codable, CaseIterable, Sendable {
    case dailyRevenue       = "daily_revenue"
    case weeklyTicketCount  = "weekly_ticket_count"
    case monthlyAvgTicket   = "monthly_avg_ticket"
    case personalCommission = "personal_commission"
    case custom             = "custom"
}

// MARK: - GoalPeriod

public enum GoalPeriod: String, Codable, CaseIterable, Sendable {
    case daily   = "daily"
    case weekly  = "weekly"
    case monthly = "monthly"
}

// MARK: - GoalStatus

public enum GoalStatus: String, Codable, CaseIterable, Sendable {
    case active    = "active"
    case completed = "completed"
    case missed    = "missed"
}

// MARK: - Goal

public struct Goal: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var userId: String?
    public var teamId: String?
    public var goalType: GoalType
    public var targetValue: Double
    public var currentValue: Double
    public var period: GoalPeriod
    public var startDate: Date
    public var endDate: Date
    public var status: GoalStatus
    public var label: String?

    public init(
        id: String,
        userId: String? = nil,
        teamId: String? = nil,
        goalType: GoalType,
        targetValue: Double,
        currentValue: Double = 0,
        period: GoalPeriod,
        startDate: Date,
        endDate: Date,
        status: GoalStatus = .active,
        label: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.teamId = teamId
        self.goalType = goalType
        self.targetValue = targetValue
        self.currentValue = currentValue
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case id, status, label
        case userId       = "user_id"
        case teamId       = "team_id"
        case goalType     = "goal_type"
        case targetValue  = "target_value"
        case currentValue = "current_value"
        case period
        case startDate    = "start_date"
        case endDate      = "end_date"
    }

    /// Progress fraction (0…1, clamped). Pure function; testable without mocks.
    public var progressFraction: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }
}

// MARK: - GoalProgressCalculator

/// Pure stateless helper for goal progress computations.
/// 80%+ test coverage required (§46 constraint).
public enum GoalProgressCalculator: Sendable {

    /// Consecutive days a goal was hit (streak).
    /// `history` is an array of `(date, achieved)` pairs sorted ascending.
    public static func streakDays(from history: [(date: Date, achieved: Bool)]) -> Int {
        var streak = 0
        let sorted = history.sorted { $0.date < $1.date }.reversed()
        for entry in sorted {
            if entry.achieved { streak += 1 } else { break }
        }
        return streak
    }

    /// Returns milestone tier reached for this progress fraction: nil, 50, 75, or 100.
    public static func milestoneTier(fraction: Double) -> Int? {
        switch fraction {
        case 1.0...:    return 100
        case 0.75..<1.0: return 75
        case 0.50..<0.75: return 50
        default:        return nil
        }
    }

    /// Returns the exact milestones crossed when moving from `from` → `to`.
    /// E.g. from=0.4, to=0.8 → [50, 75]
    public static func newMilestonesCrossed(from: Double, to: Double) -> [Int] {
        let thresholds: [Double] = [0.50, 0.75, 1.0]
        return thresholds
            .filter { $0 > from && $0 <= to }
            .map { Int($0 * 100) }
    }
}
