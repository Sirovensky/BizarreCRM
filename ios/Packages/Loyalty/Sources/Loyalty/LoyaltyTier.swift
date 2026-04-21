import SwiftUI
import DesignSystem

/// §38 — Customer loyalty tier classification.
///
/// Raw value matches the server's lowercase string (`tier` field on
/// `LoyaltyBalance`). `Comparable` is synthesised via the `allCases`
/// ordering: bronze < silver < gold < platinum.
public enum LoyaltyTier: String, CaseIterable, Sendable, Comparable {
    case bronze
    case silver
    case gold
    case platinum

    // MARK: - Comparable

    /// Lower index in `allCases` = lower tier.
    public static func < (lhs: LoyaltyTier, rhs: LoyaltyTier) -> Bool {
        let all = allCases
        guard
            let li = all.firstIndex(of: lhs),
            let ri = all.firstIndex(of: rhs)
        else { return false }
        return li < ri
    }

    // MARK: - Display

    /// Human-readable name for badge / accessibility labels.
    public var displayName: String {
        switch self {
        case .bronze:   return "Bronze"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }

    /// Design-token colour for each tier badge.
    ///
    /// Mapping:
    /// - bronze   → `.bizarreWarning`   (warm amber — closest to bronze)
    /// - silver   → `.bizarreOnSurface` (neutral on-surface — silver-grey)
    /// - gold     → `.bizarreOrange`    (brand orange — closest to gold)
    /// - platinum → `.bizarreTeal`      (premium accent)
    public var displayColor: Color {
        switch self {
        case .bronze:   return .bizarreWarning
        case .silver:   return .bizarreOnSurface
        case .gold:     return .bizarreOrange
        case .platinum: return .bizarreTeal
        }
    }

    /// SF Symbol name for the tier icon.
    public var systemSymbol: String {
        switch self {
        case .bronze:   return "medal"
        case .silver:   return "medal.fill"
        case .gold:     return "trophy"
        case .platinum: return "crown.fill"
        }
    }

    // MARK: - Parsing

    /// Initialise from a raw server string, case-insensitively.
    /// Returns `.bronze` as the safe default when the string is unknown.
    public static func parse(_ raw: String) -> LoyaltyTier {
        LoyaltyTier(rawValue: raw.lowercased()) ?? .bronze
    }
}
