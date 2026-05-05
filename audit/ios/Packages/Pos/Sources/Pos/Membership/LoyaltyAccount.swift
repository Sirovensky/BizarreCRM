// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// DO NOT use this type in cart, catalog, customer-gate, or inspector views.
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// Immutable snapshot of a customer's loyalty standing at the time of checkout.
///
/// Assembled from `GET /api/v1/membership/customer/:id` (subscription + tier)
/// and the `getLoyaltyBalance` helper in `APIClient+Loyalty.swift`.
///
/// All money amounts are in **cents** to avoid floating-point surprises.
public struct LoyaltyAccount: Sendable, Equatable {

    /// The customer this account belongs to.
    public let customerId: Int64

    /// Current tier.  `.none` means no active membership.
    public let tier: LoyaltyTier

    /// Running points balance (earn ledger minus spend ledger).
    ///
    /// NOTE: the server loyalty-points ledger is not yet fully wired
    /// (`APIClient+Loyalty.swift` stubs this to 0 until
    /// `GET /customers/:id/loyalty-points` ships). Treat 0 as "unknown"
    /// rather than "no points" until that endpoint lands.
    public let pointsBalance: Int

    /// Points earned in the current calendar year (for tier-up display).
    public let pointsThisYear: Int

    /// Percentage discount automatically applied at checkout for this tier.
    /// Derived from `CustomerSubscriptionDTO.discountPct`. 0 for `.none`.
    public let discountPercent: Int

    // MARK: - Init

    public init(
        customerId: Int64,
        tier: LoyaltyTier,
        pointsBalance: Int,
        pointsThisYear: Int,
        discountPercent: Int
    ) {
        self.customerId = customerId
        self.tier = tier
        self.pointsBalance = max(0, pointsBalance)
        self.pointsThisYear = max(0, pointsThisYear)
        self.discountPercent = max(0, min(100, discountPercent))
    }

    // MARK: - Computed helpers

    /// Whether this account represents an active membership (non-`.none` tier).
    public var isMember: Bool { tier != .none }

    /// Discount amount in cents given a subtotal in cents.
    /// Returns 0 when `discountPercent == 0` or subtotal is zero/negative.
    public func discountCents(for subtotalCents: Int) -> Int {
        guard discountPercent > 0, subtotalCents > 0 else { return 0 }
        return Int((Double(subtotalCents) * Double(discountPercent) / 100.0).rounded())
    }

    /// Estimate points earned from a sale (1 pt per $1 spent, integer dollars).
    /// This is a client-side estimate; the server is authoritative after the sale.
    public func estimatedPointsEarned(subtotalCents: Int) -> Int {
        guard subtotalCents > 0 else { return 0 }
        return subtotalCents / 100      // 1 pt per whole dollar
    }

    /// Progress fraction (0…1) toward the next tier based on `pointsBalance`.
    public var progressToNextTier: Double {
        guard let next = tier.next else { return 1.0 }
        return tier.progressTo(next: next, currentPoints: pointsThisYear)
    }

    /// Points remaining to reach the next tier. 0 at Platinum.
    public var pointsToNextTier: Int {
        tier.pointsNeeded(currentPoints: pointsThisYear)
    }
}
