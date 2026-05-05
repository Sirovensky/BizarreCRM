import Foundation

// MARK: - LTVCalculator

/// §44.2 — Pure, stateless LTV tier classifier.
///
/// All methods are `static` — no instance state, no side effects.
/// Thresholds are configurable via `LTVThresholds` (tenant override).
public enum LTVCalculator {

    // MARK: Primary API

    /// Returns the LTV tier for `lifetimeCents` using default thresholds.
    ///
    /// - Parameter lifetimeCents: Lifetime value in integer cents (non-negative).
    /// - Returns: The matching `LTVTier`. Negative values map to `.bronze`.
    public static func tier(for lifetimeCents: Int) -> LTVTier {
        tier(for: lifetimeCents, thresholds: .default)
    }

    /// Returns the LTV tier for `lifetimeCents` using `thresholds`.
    ///
    /// Useful for tenant-overridden policies fetched from the server.
    public static func tier(for lifetimeCents: Int, thresholds: LTVThresholds) -> LTVTier {
        if lifetimeCents >= thresholds.platinumCents { return .platinum }
        if lifetimeCents >= thresholds.goldCents     { return .gold }
        if lifetimeCents >= thresholds.silverCents   { return .silver }
        return .bronze
    }

    // MARK: Convenience overloads

    /// Convenience: accepts `Double` dollars (e.g. from `CustomerAnalytics.lifetimeValue`).
    public static func tier(forDollars lifetimeDollars: Double, thresholds: LTVThresholds = .default) -> LTVTier {
        let cents = Int(lifetimeDollars * 100)
        return tier(for: cents, thresholds: thresholds)
    }

    /// Convenience: accepts `Int64` cents from DTO field `ltv_cents`.
    public static func tier(forCentsInt64 cents: Int64, thresholds: LTVThresholds = .default) -> LTVTier {
        tier(for: Int(cents), thresholds: thresholds)
    }
}
