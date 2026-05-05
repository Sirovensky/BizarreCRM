import Foundation

/// §38 — Loyalty-specific APIClient extensions.
///
/// This file is append-only. Do not remove or rename existing symbols —
/// other modules depend on them at compile time.
///
/// Routes confirmed against packages/server/src/routes/membership.routes.ts:
///   GET  /membership/tiers                    — listMembershipTiers()
///   GET  /membership/customer/:id             — getCustomerSubscription()
///   POST /membership/subscribe                — subscribeMembership()
///   POST /membership/:id/cancel               — cancelMembership()
///   POST /membership/:id/pause                — pauseMembership()
///   POST /membership/:id/resume               — resumeMembership()
///   GET  /membership/:id/payments             — getMembershipPayments()
///   GET  /membership/subscriptions            — listAllSubscriptions()
///   POST /membership/payment-link             — createMembershipPaymentLink()
///
/// Points redemption (POST /membership/:id/points/redeem) is NOT yet on the
/// server. `redeemMembershipPoints` throws APITransportError.httpStatus(501,…)
/// at runtime; callers must handle 501 gracefully (show "coming soon").

// MARK: - Points redemption DTOs

/// Request body for `POST /membership/:id/points/redeem`.
/// Server endpoint is 501 until the points ledger ships.
public struct MembershipRedeemRequest: Encodable, Sendable {
    /// Points to redeem (must be > 0).
    public let points: Int
    /// Optional note for the audit log.
    public let note: String?

    public init(points: Int, note: String? = nil) {
        self.points = points
        self.note = note
    }
}

/// Response from `POST /membership/:id/points/redeem`.
public struct MembershipRedeemResultDTO: Decodable, Sendable {
    /// Whether the redemption was accepted.
    public let redeemed: Bool
    /// Remaining points balance after redemption.
    public let remainingPoints: Int?
    /// Dollar value credited (in cents), if applicable.
    public let creditCents: Int?

    enum CodingKeys: String, CodingKey {
        case redeemed
        case remainingPoints = "remaining_points"
        case creditCents     = "credit_cents"
    }
}

// MARK: - APIClient wrappers (append-only)

public extension APIClient {

    /// Redeem loyalty points for a membership subscription.
    ///
    /// `POST /membership/:id/points/redeem`
    ///
    /// NOTE: The server endpoint is not yet implemented. This method will throw
    /// `APITransportError.httpStatus(501, …)` until the server ships the route.
    /// Callers should handle 501 by showing a "coming soon" state.
    func redeemMembershipPoints(
        subscriptionId: Int,
        points: Int,
        note: String? = nil
    ) async throws -> MembershipRedeemResultDTO {
        try await post(
            "/membership/\(subscriptionId)/points/redeem",
            body: MembershipRedeemRequest(points: points, note: note),
            as: MembershipRedeemResultDTO.self
        )
    }

    // MARK: §38.5 — Punch card expiry policy

    /// `GET /loyalty/punch-card-expiry-policy` — load tenant punch card expiry + location-sharing policy.
    func getPunchCardExpiryPolicy() async throws -> PunchCardExpiryPolicyDTO {
        try await get("/loyalty/punch-card-expiry-policy", as: PunchCardExpiryPolicyDTO.self)
    }

    /// `PUT /loyalty/punch-card-expiry-policy` — save tenant punch card expiry + location-sharing policy.
    @discardableResult
    func savePunchCardExpiryPolicy(_ policy: PunchCardExpiryPolicyDTO) async throws -> PunchCardExpiryPolicyDTO {
        try await put("/loyalty/punch-card-expiry-policy", body: policy, as: PunchCardExpiryPolicyDTO.self)
    }
}

// MARK: - PunchCardExpiryPolicyDTO

/// Networking DTO for §38.5 punch card expiry + location-sharing policy.
public struct PunchCardExpiryPolicyDTO: Codable, Sendable {
    public var expiryEnabled: Bool
    public var inactivityMonths: Int
    public var sharedAcrossLocations: Bool

    enum CodingKeys: String, CodingKey {
        case expiryEnabled = "expiry_enabled"
        case inactivityMonths = "inactivity_months"
        case sharedAcrossLocations = "shared_across_locations"
    }

    public init(expiryEnabled: Bool = false, inactivityMonths: Int = 12, sharedAcrossLocations: Bool = true) {
        self.expiryEnabled = expiryEnabled
        self.inactivityMonths = inactivityMonths
        self.sharedAcrossLocations = sharedAcrossLocations
    }
}
