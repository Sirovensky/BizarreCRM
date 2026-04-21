import Foundation
#if canImport(UIKit)
import SwiftUI
import DesignSystem
#endif

// MARK: - LTVTier

/// §44.2 — Four-tier classification of a customer's lifetime value.
///
/// Thresholds (in cents):
///   bronze  < $500      (0–49 999 ¢)
///   silver  $500–$1 500 (50 000–149 999 ¢)
///   gold    $1 500–$5 000 (150 000–499 999 ¢)
///   platinum > $5 000   (≥ 500 000 ¢)
public enum LTVTier: String, Codable, Sendable, CaseIterable, Equatable {
    case bronze
    case silver
    case gold
    case platinum

    // MARK: Default thresholds (cents)

    /// The *lower* inclusive bound for this tier, using default thresholds.
    /// Bronze is always 0; platinum has no upper bound.
    public var thresholdCents: Int {
        switch self {
        case .bronze:   return 0
        case .silver:   return 50_000       // $500
        case .gold:     return 150_000      // $1 500
        case .platinum: return 500_000      // $5 000
        }
    }

    // MARK: Display

    public var label: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }

    public var icon: String {
        switch self {
        case .bronze:   return "medal"
        case .silver:   return "medal.fill"
        case .gold:     return "star.circle.fill"
        case .platinum: return "crown.fill"
        }
    }

#if canImport(UIKit)
    /// Brand-token color for the tier badge.
    public var color: Color {
        switch self {
        case .bronze:   return .bizarreWarning.opacity(0.75)   // warm amber / bronze-ish
        case .silver:   return .bizarreOnSurfaceMuted          // neutral silver
        case .gold:     return .bizarreWarning                 // full amber / gold
        case .platinum: return .bizarreTeal                    // teal distinguishes from gold
        }
    }
#endif
}
