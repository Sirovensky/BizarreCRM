import Foundation

/// §38 — Pure helper that computes the cart discount unlocked by a membership.
///
/// All functions are `static`; no state, no side effects.
///
/// **POS integration:**
/// ```swift
/// let discount = MembershipPerkApplier.discount(
///     cart: LoyaltyCart(subtotalCents: cart.subtotalCents),
///     membership: customer.activeMembership,
///     plan: plans.first { $0.id == customer.activeMembership?.planId }
/// )
/// cart.applyMemberDiscount(cents: discount)
/// ```
public enum MembershipPerkApplier {

    // MARK: - Public API

    /// Compute the total discount in cents for `cart` given the customer's `membership`.
    ///
    /// - Returns: 0 when `membership` is nil, not active, or plan has no discount perks.
    /// - Returns: Discount in cents, capped at `cart.subtotalCents` (never negative).
    ///
    /// When multiple perks exist, the largest single discount wins — perks do NOT stack
    /// by default (configurable in future via `LoyaltyRule.stackPerks`).
    public static func discount(
        cart: LoyaltyCart,
        membership: Membership?,
        plan: MembershipPlan?
    ) -> Int {
        guard
            let membership,
            membership.status.perksActive,
            let plan
        else { return 0 }

        let subtotal = cart.subtotalCents
        guard subtotal > 0 else { return 0 }

        // Collect all discount amounts from perks; pick the largest.
        let discounts: [Int] = plan.perks.compactMap { perk in
            discountCents(perk: perk, subtotalCents: subtotal)
        }

        let best = discounts.max() ?? 0
        // Cap at subtotal so we never produce a negative cart total.
        return min(best, subtotal)
    }

    // MARK: - Private helpers

    /// Compute discount for a single perk, or `nil` if the perk grants no cash discount.
    private static func discountCents(perk: MembershipPerk, subtotalCents: Int) -> Int? {
        switch perk {
        case .percentageDiscount(let pct):
            guard pct > 0 else { return nil }
            // Integer percentage rounded down.
            return (subtotalCents * pct) / 100

        case .fixedDiscount(let cents):
            guard cents > 0 else { return nil }
            return cents

        case .freeService, .exclusiveAccess:
            // These perks have no direct POS cash value — handled elsewhere.
            return nil
        }
    }
}
