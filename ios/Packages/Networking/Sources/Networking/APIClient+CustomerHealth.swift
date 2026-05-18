import Foundation

// MARK: - DTO types

/// `GET /crm/customers/:id/health-score` — data payload.
public struct CustomerHealthScoreResponse: Decodable, Sendable {
    /// Stored 0–100 score (nil when never computed).
    public let score: Int?
    /// Server label: "champion" | "loyal" | "promising" | "at_risk" | "needs_attention" | "new"
    public let tier: String?
    public let lastInteractionAt: String?
    /// Lifetime value in cents (server uses integer cents).
    public let lifetimeValueCents: Int?

    enum CodingKeys: String, CodingKey {
        case score, tier
        case lastInteractionAt  = "last_interaction_at"
        case lifetimeValueCents = "lifetime_value_cents"
    }
}

/// `POST /crm/customers/:id/health-score/recalculate` — data payload.
public struct CustomerHealthRecalcResponse: Decodable, Sendable {
    public let score: Int
    public let tier: String?
    public let recencyPoints: Int?
    public let frequencyPoints: Int?
    public let monetaryPoints: Int?
    public let ltvTier: String?
    public let lifetimeValueCents: Int?
    public let lastInteractionAt: String?

    enum CodingKeys: String, CodingKey {
        case score, tier
        case recencyPoints    = "recency_points"
        case frequencyPoints  = "frequency_points"
        case monetaryPoints   = "monetary_points"
        case ltvTier          = "ltv_tier"
        case lifetimeValueCents = "lifetime_value_cents"
        case lastInteractionAt  = "last_interaction_at"
    }
}

/// `GET /crm/customers/:id/ltv-tier` — data payload.
public struct CustomerLTVTierResponse: Decodable, Sendable {
    public let tier: String
    public let lifetimeValueCents: Int

    enum CodingKeys: String, CodingKey {
        case tier
        case lifetimeValueCents = "lifetime_value_cents"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    // BUGHUNT-2026-05-17: all three wrappers below used `/crm/...` bare
    // paths. iOS APIClient base URL is the shop origin; server mounts
    // crm.routes at `/api/v1/crm` (index.ts L1768). Customer health
    // score, RFM recalculate, and LTV tier all 404'd silently — the
    // customer detail RFM panel just rendered "Health score unavailable"
    // for every customer.

    /// `GET /api/v1/crm/customers/:id/health-score`
    /// Returns the DB-cached health score + LTV for a customer.
    /// Throws `APITransportError.notImplemented` when the endpoint is absent.
    func customerHealthScore(customerId: Int64) async throws -> CustomerHealthScoreResponse {
        try await get(
            "/api/v1/crm/customers/\(customerId)/health-score",
            as: CustomerHealthScoreResponse.self
        )
    }

    /// `POST /api/v1/crm/customers/:id/health-score/recalculate`
    /// Triggers server-side RFM recomputation and returns the updated score.
    func recalculateCustomerHealthScore(customerId: Int64) async throws -> CustomerHealthRecalcResponse {
        try await post(
            "/api/v1/crm/customers/\(customerId)/health-score/recalculate",
            body: EmptyBody(),
            as: CustomerHealthRecalcResponse.self
        )
    }

    /// `GET /api/v1/crm/customers/:id/ltv-tier`
    /// Returns the stored LTV tier + lifetime_value_cents.
    func customerLTVTier(customerId: Int64) async throws -> CustomerLTVTierResponse {
        try await get(
            "/api/v1/crm/customers/\(customerId)/ltv-tier",
            as: CustomerLTVTierResponse.self
        )
    }
}

// EmptyBody defined in NotificationsEndpoints.swift (public, module-wide).
