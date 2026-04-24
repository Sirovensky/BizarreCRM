// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// This view-model MUST only be instantiated from:
//   • PosTenderMethodPickerView (or Agent D's TenderV2 equivalents)
//   • PosReceiptView / PosPostSaleView (post-sale tier-progress row)
//
// DO NOT instantiate from cart, catalog, customer-gate, or inspector views.
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Observation
import Core

/// View-model for the checkout loyalty surfaces (tender banner + receipt row).
///
/// Lifecycle:
/// 1. Call `load(customerId:)` when entering the tender screen (after customer
///    is attached and cart is finalized).
/// 2. Observe `account` to show/hide `MembershipBenefitBanner`.
/// 3. Call `redeem(points:cartTotalCents:)` when the cashier confirms a
///    redemption from `RedeemPointsSheet`.
/// 4. After a successful sale, read `pointsToEarn` to populate
///    `MembershipTierProgressView`.
@MainActor
@Observable
public final class MembershipViewModel {

    // MARK: - Published state

    /// The customer's loyalty account. `nil` while loading, or when the customer
    /// is a walk-in / has no membership. Views must hide loyalty UI when nil.
    public private(set) var account: LoyaltyAccount?

    /// Whether a network load is in progress.
    public private(set) var isLoading: Bool = false

    /// User-facing error message. `nil` when no error.
    public private(set) var errorMessage: String?

    /// Discount cents applied via point redemption ($1 per 10 pts, or per
    /// server-returned credit). Updated after a successful `redeem` call.
    public private(set) var saved: Int = 0

    /// Estimated points the customer will earn from this sale (1 pt / $1).
    /// Updated when `cartSubtotalCents` is set.
    public private(set) var pointsToEarn: Int = 0

    /// Points the cashier has requested to redeem in the current session.
    /// Resets to 0 on `clearRedemption()` or when a new customer loads.
    public private(set) var redeemPoints: Int = 0

    // MARK: - Dependencies / inputs

    /// Cart subtotal used to compute `pointsToEarn` and validate redeem limits.
    /// Set before calling `load(customerId:)` and keep updated as items change.
    public var cartSubtotalCents: Int = 0 {
        didSet { recalcPointsToEarn() }
    }

    private let repository: LoyaltyRepository

    // MARK: - Init

    public init(repository: LoyaltyRepository) {
        self.repository = repository
    }

    // MARK: - Load

    /// Fetch the loyalty account for `customerId`.
    /// Clears any previous redemption state before the fetch.
    public func load(customerId: Int64) async {
        clearRedemption()
        account = nil
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            account = try await repository.fetchAccount(customerId: customerId)
            recalcPointsToEarn()
        } catch {
            AppLog.pos.error("MembershipViewModel.load: \(error)")
            errorMessage = "Could not load loyalty info."
        }
    }

    // MARK: - Redemption

    /// Apply `points` as a discount on the current cart.
    ///
    /// Validates:
    ///  - `points ≤ account.pointsBalance`
    ///  - equivalent discount `≤ cartSubtotalCents` (can't discount past zero)
    ///
    /// On success updates `redeemPoints` and `saved`.
    /// Throws `LoyaltyRedemptionError` on validation failure.
    /// Throws `APITransportError.httpStatus(501,…)` when the server endpoint
    /// is not yet deployed — callers should show a "coming soon" state.
    public func redeem(points: Int, invoiceId: Int64? = nil) async throws {
        guard let acct = account else { return }
        guard points > 0 else { throw LoyaltyRedemptionError.invalidPointsAmount }

        // Validate ≤ balance
        if points > acct.pointsBalance {
            throw LoyaltyRedemptionError.insufficientPoints(
                available: acct.pointsBalance,
                requested: points
            )
        }

        // Validate discount ≤ cart total (100 pts = $10 = 1000 cents)
        let discountCents = pointsToCents(points)
        if discountCents > cartSubtotalCents {
            throw LoyaltyRedemptionError.exceedsCartTotal(
                discountCents: discountCents,
                cartTotalCents: cartSubtotalCents
            )
        }

        let credited = try await repository.redeemPoints(
            customerId: acct.customerId,
            points: points,
            invoiceId: invoiceId
        )

        redeemPoints = points
        saved = credited > 0 ? credited : discountCents   // fall back to local estimate
    }

    /// Remove any applied point redemption.
    public func clearRedemption() {
        redeemPoints = 0
        saved = 0
    }

    // MARK: - Validation helpers (used by RedeemPointsSheet)

    /// Maximum points the cashier can apply: capped by balance and cart total.
    public var maxRedeemablePoints: Int {
        guard let acct = account, acct.pointsBalance > 0 else { return 0 }
        let maxFromCart = cartSubtotalCents / 100 * 10    // $1 per 10 pts inverse
        return min(acct.pointsBalance, maxFromCart)
    }

    /// Cents value of `n` points (10 pts = $1 = 100 cents).
    public func pointsToCents(_ pts: Int) -> Int {
        pts * 10   // 10 pts = $1.00 = 100 cents
    }

    /// Points equivalent of `cents` (rounded down).
    public func centsToPoints(_ cents: Int) -> Int {
        cents / 10
    }

    // MARK: - Private

    private func recalcPointsToEarn() {
        pointsToEarn = account?.estimatedPointsEarned(subtotalCents: cartSubtotalCents) ?? 0
    }
}
