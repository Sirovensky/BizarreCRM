import Foundation
import Networking

// MARK: - CustomerHealthLabel

/// Server-assigned label derived from the 0–100 RFM score.
/// Maps the string values the server stores in `health_label`.
public enum CustomerHealthLabel: String, Sendable, Equatable, CaseIterable {
    case champion
    case loyal
    case promising
    case atRisk      = "at_risk"
    case needsAttention = "needs_attention"
    case new

    /// Human-readable display string.
    public var displayTitle: String {
        switch self {
        case .champion:       return "Champion"
        case .loyal:          return "Loyal"
        case .promising:      return "Promising"
        case .atRisk:         return "At Risk"
        case .needsAttention: return "Needs Attention"
        case .new:            return "New"
        }
    }
}

// MARK: - HealthScoreComponents

/// Breakdown of the three RFM scoring pillars.
/// Non-nil only after a server recalculation (`POST …/health-score/recalculate`).
public struct HealthScoreComponents: Sendable, Equatable {
    /// Points earned from recency of last interaction (0–40).
    public let recencyPoints: Int
    /// Points earned from visit frequency (0–30).
    public let frequencyPoints: Int
    /// Points earned from total monetary spend (0–30).
    public let monetaryPoints: Int

    public init(recencyPoints: Int, frequencyPoints: Int, monetaryPoints: Int) {
        self.recencyPoints   = recencyPoints
        self.frequencyPoints = frequencyPoints
        self.monetaryPoints  = monetaryPoints
    }
}

// MARK: - CustomerHealthScoreResult

/// Computed or server-provided health result.
///
/// ## Scoring rules (client-side path, mirroring server RFM logic)
///
/// **Recency** (0–40 pts — matches crm.routes.ts:1135-1138):
///   - ≤ 30 days  → 40 pts
///   - ≤ 60 days  → 30 pts
///   - ≤ 90 days  → 20 pts
///   - ≤ 180 days → 10 pts
///   - > 180 days →  0 pts
///
/// **Frequency** (0–30 pts — visits via open-ticket proxy):
///   - ≥ 10 visits → 30 pts
///   - ≥ 5 visits  → 25 pts
///   - ≥ 3 visits  → 15 pts
///   - ≥ 1 visit   →  5 pts
///   - 0 visits    →  0 pts
///
/// **Monetary** (0–30 pts — total spend in dollars):
///   - ≥ $1 000 → 30 pts
///   - ≥ $500   → 25 pts
///   - ≥ $200   → 15 pts
///   - ≥ $50    →  5 pts
///   - < $50    →  0 pts
///
/// Total clamped to [0, 100].
/// All-nil fields → neutral 50 (yellow) with no recommendation.
/// Server score (when present on `CustomerDetail.healthScore`) takes precedence.
public struct CustomerHealthScoreResult: Sendable, Equatable {
    /// Final 0–100 score.
    public let value: Int
    /// Colour tier derived from value.
    public let tier: CustomerHealthTier
    /// Optional server-supplied label (champion / loyal / promising / at_risk / needs_attention / new).
    public let label: CustomerHealthLabel?
    /// Recommended action for the CRM user (nil when none warranted).
    public let recommendation: String?
    /// Per-pillar breakdown — non-nil only when server recalc data is available.
    public let components: HealthScoreComponents?

    public init(
        value: Int,
        tier: CustomerHealthTier,
        label: CustomerHealthLabel?,
        recommendation: String?,
        components: HealthScoreComponents? = nil
    ) {
        self.value          = value
        self.tier           = tier
        self.label          = label
        self.recommendation = recommendation
        self.components     = components
    }

    // MARK: - Pure computation

    /// Computes a health score from a `CustomerDetail`.
    ///
    /// Priority:
    ///  1. Use `detail.healthScore` when the server already computed it.
    ///  2. Fall back to client-side RFM heuristics.
    public static func compute(detail: CustomerDetail) -> CustomerHealthScoreResult {
        if let serverScore = detail.healthScore {
            let clamped = max(0, min(100, serverScore))
            let tier    = CustomerHealthTier(score: clamped)
            let label   = detail.healthLabel.flatMap { CustomerHealthLabel(rawValue: $0) }
            let rec     = recommendation(for: detail)
            return CustomerHealthScoreResult(
                value: clamped, tier: tier, label: label, recommendation: rec
            )
        }
        return clientSideRFM(detail: detail)
    }

    // MARK: - Client-side RFM

    private static func clientSideRFM(detail: CustomerDetail) -> CustomerHealthScoreResult {
        let hasRecency   = detail.lastVisitAt != nil
        let hasFrequency = detail.openTicketCount != nil
        let hasMonetary  = detail.totalSpentCents != nil

        guard hasRecency || hasFrequency || hasMonetary else {
            return CustomerHealthScoreResult(value: 50, tier: .yellow, label: nil, recommendation: nil)
        }

        let recency   = recencyPoints(for: detail)
        let frequency = frequencyPoints(for: detail)
        let monetary  = monetaryPoints(for: detail)

        let raw     = recency + frequency + monetary
        let clamped = max(0, min(100, raw))
        let tier    = CustomerHealthTier(score: clamped)
        let rec     = recommendation(for: detail)

        let components = HealthScoreComponents(
            recencyPoints:   recency,
            frequencyPoints: frequency,
            monetaryPoints:  monetary
        )
        return CustomerHealthScoreResult(
            value: clamped, tier: tier, label: nil, recommendation: rec, components: components
        )
    }

    // MARK: - Pillar helpers

    static func recencyPoints(for detail: CustomerDetail) -> Int {
        guard let raw = detail.lastVisitAt,
              let date = DateParser.parseISO8601(raw) else { return 0 }
        let days = DateParser.daysSince(date)
        if days <= 30  { return 40 }
        if days <= 60  { return 30 }
        if days <= 90  { return 20 }
        if days <= 180 { return 10 }
        return 0
    }

    static func frequencyPoints(for detail: CustomerDetail) -> Int {
        // Proxy: use totalTickets from analytics when available; fall back to 0.
        // `openTicketCount` from CustomerDetail is a partial count used for penalty;
        // real visit frequency requires CustomerAnalytics.totalTickets (passed separately).
        // When only openTicketCount is present we use it as a lower-bound proxy.
        let visits = detail.openTicketCount ?? 0
        if visits >= 10 { return 30 }
        if visits >= 5  { return 25 }
        if visits >= 3  { return 15 }
        if visits >= 1  { return 5  }
        return 0
    }

    static func monetaryPoints(for detail: CustomerDetail) -> Int {
        guard let cents = detail.totalSpentCents else { return 0 }
        let dollars = Double(cents) / 100.0
        if dollars >= 1_000 { return 30 }
        if dollars >= 500   { return 25 }
        if dollars >= 200   { return 15 }
        if dollars >= 50    { return 5  }
        return 0
    }

    // MARK: - Recommendation

    static func recommendation(for detail: CustomerDetail) -> String? {
        if let complaints = detail.complaintCount, complaints > 0 {
            return "Open complaint awaiting response."
        }
        if let raw = detail.lastVisitAt,
           let date = DateParser.parseISO8601(raw),
           DateParser.daysSince(date) > 180 {
            return "Haven't seen in 180 days — send follow-up."
        }
        return nil
    }
}

// MARK: - DateParser (internal)

/// ISO-8601 parsing helpers shared within the Health module.
enum DateParser {
    static func parseISO8601(_ raw: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: raw) { return d }
        full.formatOptions = [.withInternetDateTime]
        if let d = full.date(from: raw) { return d }
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        simple.locale = Locale(identifier: "en_US_POSIX")
        simple.timeZone = TimeZone(secondsFromGMT: 0)
        return simple.date(from: String(raw.prefix(10)))
    }

    static func daysSince(_ date: Date, relativeTo now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(date) / 86_400))
    }
}
