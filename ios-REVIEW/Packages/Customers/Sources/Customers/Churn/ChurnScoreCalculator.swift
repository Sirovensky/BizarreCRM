import Foundation

// MARK: - ChurnScoreCalculator

/// §44.3 — Pure, stateless client-side churn probability estimator.
///
/// The server score (when available) is authoritative. This calculator
/// provides a real-time fallback so the UI is never empty while the
/// server score is loading or offline.
///
/// **Formula** (additive from base 50):
///   Base:                            50
///   Days since last visit ≥ 180:    +25
///   Days since last visit 90–179:   +10
///   Days since last visit 30–89:     +5
///   Visit frequency decline:        +10
///   Support complaints (each, max 3): +8 each → max +24
///   NPS ≤ 4 (detractor):            +12
///   NPS 5–6 (passive):               +5
///   NPS 7–8 (neutral):                0
///   NPS ≥ 9 (promoter):             −12
///   LTV declining:                  +10
///   LTV growing:                    −8
///
/// Result clamped to 0–100.
public enum ChurnScoreCalculator {

    // MARK: Public API

    /// Computes a churn score for the given `input`.
    public static func compute(input: ChurnInput) -> ChurnScore {
        var score  = 50
        var factors: [String] = []

        // Days since last visit
        if let days = input.daysSinceLastVisit {
            if days >= 180 {
                score  += 25
                factors.append("180+ days since last visit")
            } else if days >= 90 {
                score  += 10
                factors.append("90+ days since last visit")
            } else if days >= 30 {
                score  += 5
                factors.append("30+ days since last visit")
            }
        }

        // Visit frequency decline
        if input.visitFrequencyDecline {
            score  += 10
            factors.append("Visit frequency decline")
        }

        // Support complaints (cap at 3)
        let capped = min(input.supportComplaints, 3)
        if capped > 0 {
            score  += capped * 8
            factors.append("\(capped) support complaint\(capped > 1 ? "s" : "")")
        }

        // NPS score
        if let nps = input.npsScore {
            if nps <= 4 {
                score  += 12
                factors.append("Low NPS score (\(nps))")
            } else if nps <= 6 {
                score  += 5
                factors.append("Passive NPS score (\(nps))")
            } else if nps >= 9 {
                score  -= 12
                // Negative factor (bonus): don't add to factors list — only negatives shown
            }
        }

        // LTV trend
        switch input.ltvTrend {
        case .declining:
            score  += 10
            factors.append("Declining lifetime value")
        case .growing:
            score  -= 8
        case .stable:
            break
        }

        let clamped = max(0, min(100, score))
        return ChurnScore(
            probability0to100: clamped,
            factors:           factors,
            riskLevel:         ChurnRiskLevel(probability: clamped)
        )
    }
}
