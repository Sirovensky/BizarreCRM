import Foundation
import Networking

// MARK: - CustomerHealthTier

/// Color tier derived from the 0–100 health score.
/// Green ≥ 70, Yellow 40–69, Red < 40.
public enum CustomerHealthTier: String, Sendable, Equatable {
    case green, yellow, red

    public init(score: Int) {
        if score >= 70 { self = .green }
        else if score >= 40 { self = .yellow }
        else { self = .red }
    }
}

// MARK: - CustomerHealthScore

/// Holds a computed (or server-provided) health result.
public struct CustomerHealthScore: Sendable, Equatable {
    public let value: Int                          // 0–100
    public let tier: CustomerHealthTier
    public let recommendation: String?

    public init(value: Int, tier: CustomerHealthTier, recommendation: String?) {
        self.value = value
        self.tier = tier
        self.recommendation = recommendation
    }

    // MARK: Static compute

    /// Pure, deterministic computation from a `CustomerDetail`.
    ///
    /// Priority order for health score:
    /// 1. Use `detail.healthScore` when the server already computed it.
    /// 2. Fall back to client-side RFM heuristics using available fields.
    ///
    /// Scoring (client-side path):
    /// - Recency (last visit): up to 30 pts — 30 if ≤30 d, 25 if ≤60 d,
    ///   20 if ≤90 d, 10 if ≤180 d, 0 beyond that.
    /// - Open ticket penalty: −10 per open ticket, capped at −20.
    /// - Complaint penalty: −15 per complaint, capped at −30.
    /// - Total spend (scaled 10–40 pts): ≥ $1 000→40, ≥ $500→30, ≥ $200→20,
    ///   ≥ $50→10, else 0. Neutral 50 when all fields nil.
    ///
    /// Recommendation rules (applied after scoring):
    /// - lastVisit > 180 days → "Haven't seen in 180 days — send follow-up."
    /// - complaintCount > 0  → "Open complaint awaiting response."
    /// - otherwise nil.
    public static func compute(detail: CustomerDetail) -> CustomerHealthScore {
        // If the server sent a pre-computed score, trust it; derive tier + recommendation.
        if let serverScore = detail.healthScore {
            let clamped = max(0, min(100, serverScore))
            let tier = CustomerHealthTier(score: clamped)
            let rec = recommendation(for: detail)
            return CustomerHealthScore(value: clamped, tier: tier, recommendation: rec)
        }

        // Client-side heuristic path.
        let allNil = detail.lastVisitAt == nil
            && detail.openTicketCount == nil
            && detail.complaintCount == nil
            && detail.totalSpentCents == nil

        guard !allNil else {
            return CustomerHealthScore(value: 50, tier: .yellow, recommendation: nil)
        }

        var score = 0

        // Recency (0–30 pts).
        if let lastVisitAt = detail.lastVisitAt, let date = parseISO8601(lastVisitAt) {
            let days = daysSince(date)
            if days <= 30 { score += 30 }
            else if days <= 60 { score += 25 }
            else if days <= 90 { score += 20 }
            else if days <= 180 { score += 10 }
        }

        // Open ticket penalty (−10 each, max −20).
        let openTickets = detail.openTicketCount ?? 0
        let ticketPenalty = min(openTickets * 10, 20)
        score -= ticketPenalty

        // Complaint penalty (−15 each, max −30).
        let complaints = detail.complaintCount ?? 0
        let complaintPenalty = min(complaints * 15, 30)
        score -= complaintPenalty

        // Spend (0–40 pts). `totalSpentCents` is in cents.
        if let spentCents = detail.totalSpentCents {
            let dollars = Double(spentCents) / 100.0
            if dollars >= 1_000 { score += 40 }
            else if dollars >= 500 { score += 30 }
            else if dollars >= 200 { score += 20 }
            else if dollars >= 50 { score += 10 }
        }

        let clamped = max(0, min(100, score))
        let tier = CustomerHealthTier(score: clamped)
        let rec = recommendation(for: detail)
        return CustomerHealthScore(value: clamped, tier: tier, recommendation: rec)
    }

    // MARK: Private helpers

    private static func recommendation(for detail: CustomerDetail) -> String? {
        // Complaint check takes priority.
        if let complaints = detail.complaintCount, complaints > 0 {
            return "Open complaint awaiting response."
        }
        // Recency check.
        if let lastVisitAt = detail.lastVisitAt, let date = parseISO8601(lastVisitAt) {
            if daysSince(date) > 180 {
                return "Haven't seen in 180 days — send follow-up."
            }
        }
        return nil
    }

    /// ISO-8601 subset parser. Returns nil on malformed input.
    static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: raw) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        if let d = formatter.date(from: raw) { return d }
        // Fallback: date-only "YYYY-MM-DD"
        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        simple.locale = Locale(identifier: "en_US_POSIX")
        simple.timeZone = TimeZone(secondsFromGMT: 0)
        return simple.date(from: String(raw.prefix(10)))
    }

    /// Days elapsed since `date`, using calendar-day granularity.
    static func daysSince(_ date: Date, relativeTo now: Date = Date()) -> Int {
        let diff = now.timeIntervalSince(date)
        return max(0, Int(diff / 86_400))
    }
}
