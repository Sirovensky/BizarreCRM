import Foundation
import Networking

// MARK: - LeadScoreInput

/// Inputs for score calculation. All numeric values are optional so callers
/// can pass whatever subset the lead record provides.
public struct LeadScoreInput: Sendable {
    /// Number of times the lead has been contacted (calls, SMS, email).
    public let engagementCount: Int
    /// Days since last contact attempt. `nil` = never contacted.
    public let daysSinceLastContact: Int?
    /// Whether the lead has indicated a budget (non-nil, > 0).
    public let budgetCents: Int?
    /// Days until the stated decision deadline. `nil` = unknown.
    public let daysUntilDeadline: Int?
    /// Raw source string from the Lead record.
    public let source: String?

    public init(
        engagementCount: Int = 0,
        daysSinceLastContact: Int? = nil,
        budgetCents: Int? = nil,
        daysUntilDeadline: Int? = nil,
        source: String? = nil
    ) {
        self.engagementCount = engagementCount
        self.daysSinceLastContact = daysSinceLastContact
        self.budgetCents = budgetCents
        self.daysUntilDeadline = daysUntilDeadline
        self.source = source
    }
}

// MARK: - LeadScoreCalculator

/// Pure, synchronous score calculator. No side effects, no I/O.
/// Weights sum to 100; each factor contributes a 0–weight score.
public enum LeadScoreCalculator {

    // MARK: - Weights

    private static let engagementWeight:     Double = 30
    private static let contactVelocityWeight: Double = 25
    private static let budgetWeight:          Double = 20
    private static let timelineWeight:        Double = 15
    private static let sourceWeight:          Double = 10

    // MARK: - API

    /// Compute a `LeadScore` for `leadId` from the provided inputs.
    public static func compute(leadId: Int64, input: LeadScoreInput) -> LeadScore {
        var totalScore: Double = 0
        var factors: [String] = []

        // 1. Engagement — contacts up to 5 max out the factor.
        let engRaw = min(Double(input.engagementCount), 5.0) / 5.0
        let engScore = engRaw * engagementWeight
        totalScore += engScore
        if input.engagementCount == 0 {
            factors.append("No engagement yet")
        } else if input.engagementCount >= 5 {
            factors.append("High engagement (\(input.engagementCount) contacts)")
        } else {
            factors.append("Moderate engagement (\(input.engagementCount) contacts)")
        }

        // 2. Contact velocity — recent contact = high velocity.
        let velocityScore: Double
        if let days = input.daysSinceLastContact {
            // >30 days = zero; ≤0 days = full.
            let ratio = max(0.0, 1.0 - Double(days) / 30.0)
            velocityScore = ratio * contactVelocityWeight
            if days == 0 {
                factors.append("Contacted today")
            } else if days <= 7 {
                factors.append("Contacted \(days)d ago")
            } else {
                factors.append("Last contact \(days)d ago")
            }
        } else {
            velocityScore = 0
            factors.append("Never contacted")
        }
        totalScore += velocityScore

        // 3. Budget indicated — any positive budget = full weight.
        let budgetScore: Double
        if let cents = input.budgetCents, cents > 0 {
            budgetScore = budgetWeight
            let dollars = cents / 100
            factors.append("Budget indicated: $\(dollars)")
        } else {
            budgetScore = 0
            factors.append("No budget indicated")
        }
        totalScore += budgetScore

        // 4. Timeline urgency — decision within 30 days = full weight.
        let timelineScore: Double
        if let days = input.daysUntilDeadline {
            if days <= 0 {
                // Overdue deadline — still counts positively (they need action).
                timelineScore = timelineWeight
                factors.append("Decision overdue")
            } else if days <= 30 {
                timelineScore = max(0, (1.0 - Double(days) / 30.0)) * timelineWeight + timelineWeight * 0.5
                factors.append("Decision in \(days)d")
            } else {
                timelineScore = 0
                factors.append("Decision >30d away")
            }
        } else {
            timelineScore = 0
            factors.append("No deadline set")
        }
        totalScore += timelineScore

        // 5. Source quality — high-intent sources score higher.
        let sourceScore = sourceQualityScore(input.source) * sourceWeight
        totalScore += sourceScore
        factors.append("Source: \(input.source ?? "unknown")")

        let clamped = max(0, min(100, Int(totalScore.rounded())))
        return LeadScore(leadId: leadId, score: clamped, factors: factors)
    }

    // MARK: - Helpers

    /// Returns 0–1 representing source quality (referral > web > phone > walkin > campaign > other).
    static func sourceQualityScore(_ source: String?) -> Double {
        switch source?.lowercased() {
        case "referral":  return 1.0
        case "web":       return 0.8
        case "phone":     return 0.7
        case "walk_in", "walkin", "walk-in": return 0.6
        case "campaign":  return 0.5
        default:          return 0.3
        }
    }
}
