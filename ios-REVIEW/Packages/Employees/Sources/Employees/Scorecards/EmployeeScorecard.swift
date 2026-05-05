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

// MARK: - §46.4 ScorecardMetricKind — objective vs subjective

/// Distinguishes auto-computed hard metrics from manager-rated subjective scores.
///
/// Objective metrics derive directly from system events (tickets closed, hours
/// logged, etc.) and are never editable by humans post-computation.
/// Subjective metrics are the 1–5 competency ratings from `§46.2` reviews and
/// may carry the manager's annotation.
public enum ScorecardMetricKind: String, Sendable, CaseIterable {
    /// Auto-computed from system events; no human editing allowed after compute.
    case objective = "objective"
    /// Manager-rated 1–5 scale from performance review competency grid.
    case subjective = "subjective"
}

/// Maps each EmployeeScorecard key path to its ScorecardMetricKind.
/// Used by `ScorecardView` to render objective metrics differently
/// (no edit control; sourced badge) from subjective ones (edit pencil; rating badge).
public enum ScorecardMetricClassifier: Sendable {
    /// Returns the kind for the given metric label.
    public static func kind(for metric: ScorecardMetric) -> ScorecardMetricKind {
        switch metric {
        case .ticketCloseRate,
             .slaCompliance,
             .revenueAttributed,
             .commissionEarned,
             .hoursWorked,
             .breaksTaken,
             .voidsTriggered,
             .overridesTriggered:
            return .objective
        case .avgCustomerRating:
            // Customer rating is from survey responses — objective (user-generated).
            return .objective
        case .managerRating:
            // Composite rating from review competency grid — subjective.
            return .subjective
        }
    }
}

/// Enumeration of all scorecard metrics for classification purposes.
public enum ScorecardMetric: String, CaseIterable, Sendable {
    case ticketCloseRate    = "ticket_close_rate"
    case slaCompliance      = "sla_compliance"
    case avgCustomerRating  = "avg_customer_rating"
    case revenueAttributed  = "revenue_attributed"
    case commissionEarned   = "commission_earned"
    case hoursWorked        = "hours_worked"
    case breaksTaken        = "breaks_taken"
    case voidsTriggered     = "voids_triggered"
    case overridesTriggered = "overrides_triggered"
    /// §46.4 Subjective — aggregated from PerformanceReview competency ratings.
    case managerRating      = "manager_rating"

    public var displayName: String {
        switch self {
        case .ticketCloseRate:    return "Ticket Close Rate"
        case .slaCompliance:      return "SLA Compliance"
        case .avgCustomerRating:  return "Avg Customer Rating"
        case .revenueAttributed:  return "Revenue Attributed"
        case .commissionEarned:   return "Commission Earned"
        case .hoursWorked:        return "Hours Worked"
        case .breaksTaken:        return "Breaks Taken"
        case .voidsTriggered:     return "Voids Triggered"
        case .overridesTriggered: return "Overrides Triggered"
        case .managerRating:      return "Manager Rating"
        }
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
