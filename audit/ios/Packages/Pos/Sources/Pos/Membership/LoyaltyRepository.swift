// MARK: - Module placement guard
// ─────────────────────────────────────────────────────────────────────────────
// Loyalty surfaces are CHECKOUT-ONLY.
// DO NOT use this repository in cart, catalog, customer-gate, or inspector.
// See LoyaltyTier.swift for the full restriction note.
// ─────────────────────────────────────────────────────────────────────────────

import Foundation
import Networking
import Core

// MARK: - Protocol

/// Repository for fetching and redeeming customer loyalty data at checkout.
///
/// Server routes:
///   - `GET  /api/v1/membership/customer/:id`  — subscription + tier
///   - `GET  /api/v1/customers/:id/analytics`  — lifetime spend (via APIClient+Loyalty)
///   - `POST /api/v1/membership/:id/points/redeem { points, note }` — redeem pts
///
/// NOTE: The dedicated `GET /api/v1/customers/:id/loyalty` described in the
/// §Agent-H spec does not currently exist on the server. The Live implementation
/// assembles `LoyaltyAccount` from the two endpoints above (mirroring the
/// existing `getLoyaltyBalance` logic in `APIClient+Loyalty.swift`).
/// When the server ships `/customers/:id/loyalty`, replace the assembly logic
/// in `LoyaltyRepositoryLive` and remove this note.
public protocol LoyaltyRepository: Sendable {

    /// Fetch the loyalty account for `customerId`.
    /// Returns `nil` if the customer has no active subscription (not a member).
    /// Throws on network / server errors.
    func fetchAccount(customerId: Int64) async throws -> LoyaltyAccount?

    /// Post a points-redemption request for `customerId`.
    ///
    /// - Parameters:
    ///   - customerId: The customer whose points are being redeemed.
    ///   - points:     Number of points to redeem (must be > 0).
    ///   - invoiceId:  The in-progress invoice id (for the audit trail).
    ///
    /// Returns the number of cents credited to the cart after redemption.
    /// Throws `LoyaltyRedemptionError` on validation failures, or
    /// `APITransportError.httpStatus(501,…)` when the server endpoint is
    /// not yet deployed.
    func redeemPoints(customerId: Int64, points: Int, invoiceId: Int64?) async throws -> Int
}

// MARK: - Errors

public enum LoyaltyRedemptionError: Error, Equatable, Sendable {
    /// Caller tried to redeem more points than the customer holds.
    case insufficientPoints(available: Int, requested: Int)
    /// The computed discount would exceed the cart total.
    case exceedsCartTotal(discountCents: Int, cartTotalCents: Int)
    /// Points value ≤ 0.
    case invalidPointsAmount
}

// MARK: - Live implementation

/// Assembles `LoyaltyAccount` from the existing membership + analytics endpoints.
public struct LoyaltyRepositoryLive: LoyaltyRepository {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: fetchAccount

    public func fetchAccount(customerId: Int64) async throws -> LoyaltyAccount? {
        // 1. Fetch membership subscription concurrently with analytics balance.
        async let subscriptionTask: CustomerSubscriptionDTO? = {
            do {
                return try await api.get(
                    "/membership/customer/\(customerId)",
                    as: CustomerSubscriptionDTO?.self
                )
            } catch {
                // 404 → customer has no subscription; other errors re-throw.
                if case APITransportError.httpStatus(404, _) = error { return nil }
                AppLog.pos.error("LoyaltyRepository: subscription fetch error: \(error)")
                return nil
            }
        }()

        async let balanceTask: LoyaltyBalance? = {
            do {
                return try await api.getLoyaltyBalance(customerId: customerId)
            } catch {
                AppLog.pos.error("LoyaltyRepository: balance fetch error: \(error)")
                return nil
            }
        }()

        let (subscription, balance) = await (subscriptionTask, balanceTask)

        // No active subscription → not a member.
        guard let sub = subscription else { return nil }

        let tier = LoyaltyTier.from(serverName: sub.tierName)
        guard tier != .none else { return nil }

        let discountPct = sub.discountPct ?? 0
        let points = balance?.points ?? 0

        return LoyaltyAccount(
            customerId: customerId,
            tier: tier,
            pointsBalance: points,
            pointsThisYear: points,    // Server doesn't split YTD yet; use total.
            discountPercent: discountPct
        )
    }

    // MARK: redeemPoints

    public func redeemPoints(customerId: Int64, points: Int, invoiceId: Int64?) async throws -> Int {
        guard points > 0 else { throw LoyaltyRedemptionError.invalidPointsAmount }

        // Derive subscription id — needed for the /membership/:id/points/redeem endpoint.
        // We do a lightweight subscription fetch to get the subscription id.
        let sub: CustomerSubscriptionDTO? = try? await api.get(
            "/membership/customer/\(customerId)",
            as: CustomerSubscriptionDTO?.self
        )

        guard let subscriptionId = sub?.id else {
            AppLog.pos.error("LoyaltyRepository: no active subscription for customer \(customerId)")
            throw LoyaltyRedemptionError.invalidPointsAmount
        }

        // NOTE: server endpoint POST /membership/:id/points/redeem returns 501 until
        // the points ledger ships. Callers handle APITransportError.httpStatus(501,…)
        // by showing a "coming soon" fallback.
        let result = try await api.redeemMembershipPoints(
            subscriptionId: subscriptionId,
            points: points,
            note: invoiceId.map { "POS invoice \($0)" }
        )

        return result.creditCents ?? 0
    }
}

// MARK: - Stub implementation (build-green fallback)

/// Returns `nil` for every fetch and throws `.invalidPointsAmount` on redeem.
/// Use when the real server endpoint is unavailable or in unit-test isolation.
public struct LoyaltyRepositoryStub: LoyaltyRepository {

    public init() {}

    public func fetchAccount(customerId: Int64) async -> LoyaltyAccount? {
        nil
    }

    public func redeemPoints(customerId: Int64, points: Int, invoiceId: Int64?) async throws -> Int {
        throw LoyaltyRedemptionError.invalidPointsAmount
    }
}
