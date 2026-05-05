import Foundation

// MARK: - LeadScore

/// Computed score for a lead, 0–100. Immutable; recreate to update.
public struct LeadScore: Sendable, Equatable {
    public let leadId: Int64
    /// Normalised 0–100 integer.
    public let score: Int
    /// Human-readable factor descriptions, ordered by descending weight.
    public let factors: [String]
    public let computedAt: Date

    public init(leadId: Int64, score: Int, factors: [String], computedAt: Date = Date()) {
        self.leadId = leadId
        self.score = max(0, min(100, score))
        self.factors = factors
        self.computedAt = computedAt
    }
}
