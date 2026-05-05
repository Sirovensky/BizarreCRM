import Foundation

// MARK: - ScoreCriterion

/// The dimension a single scoring rule evaluates.
public enum ScoreCriterion: String, CaseIterable, Sendable, Hashable {
    /// How recently the lead was last contacted (lower days-since = better).
    case recency
    /// The origin channel of the lead (referral, web, phone, etc.).
    case source
    /// Whether the lead has been contacted at all.
    case contacted
}

// MARK: - LeadScoreRule

/// A single immutable scoring rule: a criterion with a relative weight.
/// Weights are positive fractions; the engine normalises them so they always
/// sum to 100 regardless of how many rules are active.
public struct LeadScoreRule: Sendable, Equatable, Identifiable {
    /// Stable identifier — use `criterion.rawValue` as default.
    public let id: String
    /// Which dimension this rule measures.
    public let criterion: ScoreCriterion
    /// Relative contribution of this rule (must be > 0).
    public let weight: Double

    public init(criterion: ScoreCriterion, weight: Double, id: String? = nil) {
        precondition(weight > 0, "LeadScoreRule weight must be > 0")
        self.criterion = criterion
        self.weight    = weight
        self.id        = id ?? criterion.rawValue
    }

    // MARK: - Default ruleset

    /// Balanced default rules used when no custom ruleset is supplied.
    public static let defaults: [LeadScoreRule] = [
        LeadScoreRule(criterion: .recency,   weight: 40),
        LeadScoreRule(criterion: .source,    weight: 35),
        LeadScoreRule(criterion: .contacted, weight: 25),
    ]
}
