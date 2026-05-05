import SwiftUI
import DesignSystem

/// §38 — Customer loyalty tier classification.
///
/// Codable conformance uses the raw string value ("bronze" etc.) which matches
/// the server's `tier` field and the `LoyaltyBalance` DTO.
///
/// Raw value matches the server's lowercase string (`tier` field on
/// `LoyaltyBalance`). `Comparable` is synthesised via the `allCases`
/// ordering: bronze < silver < gold < platinum.
public enum LoyaltyTier: String, CaseIterable, Codable, Sendable, Comparable {
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

    // MARK: - Tier thresholds

    /// Minimum cumulative lifetime spend (in cents) required to reach this tier.
    ///
    /// - bronze:   $0    (entry-level)
    /// - silver:   $500
    /// - gold:     $1,000
    /// - platinum: $5,000
    public var minLifetimeSpendCents: Int {
        switch self {
        case .bronze:   return 0
        case .silver:   return 50_000
        case .gold:     return 100_000
        case .platinum: return 500_000
        }
    }

    // MARK: - Perks summary

    /// Short human-readable description of perks for display in cards/tooltips.
    public var perksDescription: String {
        switch self {
        case .bronze:
            return "1 point per $1 spent. Welcome bonus on sign-up."
        case .silver:
            return "1 point per $1 spent. 5% discount on all services."
        case .gold:
            return "2 points per $1 spent. 10% discount. Priority service."
        case .platinum:
            return "3 points per $1 spent. 15% discount. Exclusive events & concierge support."
        }
    }

    // MARK: - Parsing

    /// Initialise from a raw server string, case-insensitively.
    /// Returns `.bronze` as the safe default when the string is unknown.
    public static func parse(_ raw: String) -> LoyaltyTier {
        LoyaltyTier(rawValue: raw.lowercased()) ?? .bronze
    }
}
