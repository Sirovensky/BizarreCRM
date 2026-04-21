import Foundation

// MARK: - ScorecardWindow

public enum ScorecardWindow: Int, CaseIterable, Sendable {
    case thirtyDays  = 30
    case ninetyDays  = 90
    case oneYear     = 365

    public var displayName: String {
        switch self {
        case .thirtyDays:  return "30 Days"
        case .ninetyDays:  return "90 Days"
        case .oneYear:     return "1 Year"
        }
    }
}

// MARK: - EmployeeScorecard

public struct EmployeeScorecard: Codable, Sendable, Identifiable, Hashable {
    public let employeeId: String
    public var ticketCloseRate: Double       // 0.0–1.0
    public var slaCompliance: Double         // 0.0–1.0
    public var avgCustomerRating: Double     // 1.0–5.0
    public var revenueAttributed: Double
    public var commissionEarned: Double
    public var hoursWorked: Double
    public var breaksTaken: Int
    public var voidsTriggered: Int
    public var overridesTriggered: Int
    public var windowDays: Int

    public var id: String { employeeId }

    public init(
        employeeId: String,
        ticketCloseRate: Double = 0,
        slaCompliance: Double = 0,
        avgCustomerRating: Double = 0,
        revenueAttributed: Double = 0,
        commissionEarned: Double = 0,
        hoursWorked: Double = 0,
        breaksTaken: Int = 0,
        voidsTriggered: Int = 0,
        overridesTriggered: Int = 0,
        windowDays: Int = 30
    ) {
        self.employeeId = employeeId
        self.ticketCloseRate = ticketCloseRate
        self.slaCompliance = slaCompliance
        self.avgCustomerRating = avgCustomerRating
        self.revenueAttributed = revenueAttributed
        self.commissionEarned = commissionEarned
        self.hoursWorked = hoursWorked
        self.breaksTaken = breaksTaken
        self.voidsTriggered = voidsTriggered
        self.overridesTriggered = overridesTriggered
        self.windowDays = windowDays
    }

    enum CodingKeys: String, CodingKey {
        case employeeId         = "employee_id"
        case ticketCloseRate    = "ticket_close_rate"
        case slaCompliance      = "sla_compliance"
        case avgCustomerRating  = "avg_customer_rating"
        case revenueAttributed  = "revenue_attributed"
        case commissionEarned   = "commission_earned"
        case hoursWorked        = "hours_worked"
        case breaksTaken        = "breaks_taken"
        case voidsTriggered     = "voids_triggered"
        case overridesTriggered = "overrides_triggered"
        case windowDays         = "window_days"
    }
}

// MARK: - ScorecardAggregator

/// Pure stateless aggregation helper. 80%+ test coverage required.
public enum ScorecardAggregator: Sendable {

    /// Compute a composite score (0–100) from a scorecard.
    /// Weights: close rate 30%, SLA 25%, rating 25%, voids/overrides penalty 20%.
    public static func compositeScore(_ card: EmployeeScorecard) -> Double {
        let closeScore  = card.ticketCloseRate * 30
        let slaScore    = card.slaCompliance * 25
        let ratingScore = ((card.avgCustomerRating - 1) / 4.0).clamped(to: 0...1) * 25
        let penaltyRate = Double(card.voidsTriggered + card.overridesTriggered) / max(card.hoursWorked, 1)
        let penaltyScore = max(0, (1 - penaltyRate) * 20)
        return closeScore + slaScore + ratingScore + penaltyScore
    }

    /// Team average across multiple scorecards for a given key path.
    public static func teamAverage(_ cards: [EmployeeScorecard], _ keyPath: KeyPath<EmployeeScorecard, Double>) -> Double {
        guard !cards.isEmpty else { return 0 }
        let sum = cards.reduce(0.0) { $0 + $1[keyPath: keyPath] }
        return sum / Double(cards.count)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
