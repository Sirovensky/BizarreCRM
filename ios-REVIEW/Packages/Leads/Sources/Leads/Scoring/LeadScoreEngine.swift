import Foundation
import Networking

// MARK: - LeadScoreEngine

/// Pure, synchronous engine that computes a 0–100 score from a configurable
/// set of `LeadScoreRule`s applied to a `Lead`.
///
/// Rules are weight-normalised so any combination of positive weights produces
/// a score in [0, 100]. No side effects, no I/O — safe for unit testing.
public enum LeadScoreEngine {

    // MARK: - Public API

    /// Compute a `LeadScore` by applying `rules` to `lead`.
    ///
    /// - Parameters:
    ///   - lead:  The lead to score.
    ///   - rules: Ordered list of rules (defaults to `LeadScoreRule.defaults`).
    ///   - now:   Reference date for recency calculations (injectable for tests).
    /// - Returns: A clamped 0–100 `LeadScore` with human-readable factors.
    public static func compute(
        lead: Lead,
        rules: [LeadScoreRule] = LeadScoreRule.defaults,
        now: Date = Date()
    ) -> LeadScore {
        guard !rules.isEmpty else {
            return LeadScore(leadId: lead.id, score: 0, factors: ["No rules configured"])
        }

        let totalWeight = rules.reduce(0.0) { $0 + $1.weight }
        var rawScore: Double = 0
        var factors: [String] = []

        for rule in rules {
            let (points, description) = evaluate(rule: rule, lead: lead, now: now)
            // Normalise this rule's contribution to its share of 100.
            let normalisedContribution = (points * rule.weight / totalWeight)
            rawScore += normalisedContribution
            factors.append(description)
        }

        // Sort factors by descending absolute contribution so most impactful
        // shows first (stable sort preserves rule order on ties).
        let clamped = max(0, min(100, Int(rawScore.rounded())))
        return LeadScore(leadId: lead.id, score: clamped, factors: factors, computedAt: now)
    }

    // MARK: - Per-criterion evaluation

    /// Returns a raw score in [0, 100] plus a factor description for one rule.
    static func evaluate(rule: LeadScoreRule, lead: Lead, now: Date) -> (Double, String) {
        switch rule.criterion {
        case .recency:
            return evaluateRecency(lead: lead, now: now)
        case .source:
            return evaluateSource(lead: lead)
        case .contacted:
            return evaluateContacted(lead: lead)
        }
    }

    // MARK: Recency (0–100)
    // "Never contacted" = 0. Contacted today = 100. >=30 days = 0.

    static func evaluateRecency(lead: Lead, now: Date) -> (Double, String) {
        guard let createdAt = lead.createdAt else {
            return (0, "No creation date")
        }
        // Parse ISO-8601 creation date as a rough recency proxy.
        // The real recency would be last-contact date; we use lead age as proxy
        // since Lead does not carry a last-contacted field.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let created: Date
        if let d = formatter.date(from: createdAt) {
            created = d
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let d = formatter.date(from: createdAt) else {
                return (0, "Unparseable date")
            }
            created = d
        }
        let days = Int(now.timeIntervalSince(created) / 86_400)
        if days <= 0 {
            return (100, "Created today")
        } else if days <= 7 {
            let score = 100.0 - Double(days) * (40.0 / 7.0) // 100 → 60
            return (score, "Created \(days)d ago")
        } else if days <= 30 {
            let score = 60.0 * (1.0 - Double(days - 7) / 23.0) // 60 → 0
            return (max(0, score), "Created \(days)d ago")
        } else {
            return (0, "Created \(days)d ago (stale)")
        }
    }

    // MARK: Source quality (0–100)

    static func evaluateSource(lead: Lead) -> (Double, String) {
        let quality = sourceQuality(lead.source)
        return (quality * 100, "Source: \(lead.source ?? "unknown")")
    }

    /// Maps source string to 0–1. Mirrors `LeadScoreCalculator.sourceQualityScore`.
    static func sourceQuality(_ source: String?) -> Double {
        switch source?.lowercased() {
        case "referral":                   return 1.0
        case "web":                        return 0.8
        case "phone":                      return 0.7
        case "walk_in", "walkin", "walk-in": return 0.6
        case "campaign":                   return 0.5
        default:                           return 0.3
        }
    }

    // MARK: Contacted (0 or 100)
    // "won" or "qualified" or "quoted" imply at least one contact attempt.

    static func evaluateContacted(lead: Lead) -> (Double, String) {
        let contactedStatuses: Set<String> = ["qualified", "quoted", "won"]
        let status = lead.status?.lowercased() ?? ""
        // A non-new, non-lost status strongly implies contact.
        if contactedStatuses.contains(status) {
            return (100, "Previously contacted (status: \(status))")
        } else if status == "lost" {
            // Lost means they were contacted but didn't convert.
            return (50, "Contacted but lost")
        } else {
            return (0, "Not yet contacted")
        }
    }
}
