import Foundation

// MARK: - LTVPerkApplier

/// §44.2 — Pure, stateless filter that returns perks applicable for a tier.
///
/// `applicablePerks(tier:perks:)` is a simple filter: it returns the subset of
/// `perks` whose `tier` matches `tier` exactly. The caller is responsible for
/// deciding whether higher tiers should inherit lower-tier perks (accumulate vs
/// replace — that policy lives in the admin editor, not here).
public enum LTVPerkApplier {

    /// Returns perks from `perks` that belong to exactly `tier`.
    ///
    /// - Parameters:
    ///   - tier: The customer's current LTV tier.
    ///   - perks: The full catalogue of configured perks (from tenant settings or defaults).
    /// - Returns: A new array containing only the matching perks. Input is never mutated.
    public static func applicablePerks(tier: LTVTier, perks: [LTVPerk]) -> [LTVPerk] {
        perks.filter { $0.tier == tier }
    }
}
