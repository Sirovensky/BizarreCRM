import Foundation

/// §38 — Pure, stateless loyalty computation helpers.
///
/// All functions are `static`; no state, no side effects, no network.
/// Thread-safe by design — safe to call from any actor.
public enum LoyaltyCalculator {

    // MARK: - Tier

    /// Determine the customer's loyalty tier from their cumulative lifetime spend.
    ///
    /// Thresholds (in cents):
    /// - bronze:    $0 – $499.99
    /// - silver:    $500 – $999.99
    /// - gold:      $1,000 – $4,999.99
    /// - platinum:  $5,000+
    ///
    /// Uses `LoyaltyTier.minLifetimeSpendCents` as the single source of truth so
    /// threshold values are co-located with the enum definition.
    public static func tier(for lifetimeSpendCents: Int) -> LoyaltyTier {
        // Walk tiers from highest to lowest; first match wins.
        for tier in LoyaltyTier.allCases.reversed() {
            if lifetimeSpendCents >= tier.minLifetimeSpendCents {
                return tier
            }
        }
        return .bronze
    }

    // MARK: - Points earn

    /// Compute points earned on a single sale.
    ///
    /// Algorithm:
    /// 1. Convert `amountCents` to whole dollars (integer division).
    /// 2. Multiply by `rule.pointsPerDollar`.
    /// 3. Apply `tuesdayMultiplier` when the sale date falls on Tuesday.
    /// 4. Apply `birthdayMultiplier` when `sale.isBirthday` is `true`.
    ///
    /// Note: Tuesday and birthday multipliers are applied separately (not stacked
    /// multiplicatively) — the larger of the two is used when both conditions hold.
    public static func points(earned sale: LoyaltySale, rule: LoyaltyRule) -> Int {
        let wholeDollars = sale.amountCents / 100
        let base = wholeDollars * rule.pointsPerDollar

        // Determine the active multiplier (largest wins; 1 = no bonus).
        var multiplier = 1
        if isTuesday(sale.date) {
            multiplier = max(multiplier, rule.tuesdayMultiplier)
        }
        if sale.isBirthday {
            multiplier = max(multiplier, rule.birthdayMultiplier)
        }

        return base * multiplier
    }

    // MARK: - Redemption

    /// Convert loyalty `points` to a discount in cents.
    ///
    /// Formula: `points * rate.centsPerPoint`.
    /// Returns 0 for negative or zero point counts.
    public static func redemption(points: Int, rate: LoyaltyRedemptionRate) -> Int {
        guard points > 0 else { return 0 }
        return points * rate.centsPerPoint
    }

    // MARK: - Expiry

    /// Compute the expiry `Date` for points earned at `earnedAt`.
    ///
    /// - Returns: `nil` when `rule.expiryDays` is ≤ 0 (points never expire).
    /// - Returns: `earnedAt` advanced by exactly `expiryDays` calendar days
    ///   (UTC-anchored so DST transitions don't shift the boundary).
    public static func expiry(earnedAt: Date, rule: LoyaltyRule) -> Date? {
        guard rule.expiryDays > 0 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(byAdding: .day, value: rule.expiryDays, to: earnedAt)
    }

    // MARK: - Private helpers

    /// Returns `true` when `date` falls on a Tuesday in the UTC timezone.
    private static func isTuesday(_ date: Date) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // weekday: 1=Sunday, 2=Monday, 3=Tuesday … 7=Saturday
        return cal.component(.weekday, from: date) == 3
    }
}
