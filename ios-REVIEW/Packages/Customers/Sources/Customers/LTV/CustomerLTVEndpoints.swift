#if canImport(UIKit)
import Foundation
import Networking

// MARK: - LTV Policy server shapes

/// Response from `GET /tenant/ltv-policy`.
public struct LTVPolicy: Codable, Sendable {
    public let silverCents:   Int
    public let goldCents:     Int
    public let platinumCents: Int
    public let perks:         [LTVPerk]?

    public init(silverCents: Int, goldCents: Int, platinumCents: Int, perks: [LTVPerk]? = nil) {
        self.silverCents   = silverCents
        self.goldCents     = goldCents
        self.platinumCents = platinumCents
        self.perks         = perks
    }

    enum CodingKeys: String, CodingKey {
        case silverCents   = "silver_cents"
        case goldCents     = "gold_cents"
        case platinumCents = "platinum_cents"
        case perks
    }
}

/// Request body for `PATCH /tenant/ltv-policy`.
public struct LTVPolicyPatch: Codable, Sendable {
    public let silverCents:   Int
    public let goldCents:     Int
    public let platinumCents: Int
    public let perks:         [LTVPerk]

    public init(silverCents: Int, goldCents: Int, platinumCents: Int, perks: [LTVPerk]) {
        self.silverCents   = silverCents
        self.goldCents     = goldCents
        self.platinumCents = platinumCents
        self.perks         = perks
    }

    enum CodingKeys: String, CodingKey {
        case silverCents   = "silver_cents"
        case goldCents     = "gold_cents"
        case platinumCents = "platinum_cents"
        case perks
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    /// `GET /tenant/ltv-policy` — fetch tenant-specific LTV tier thresholds and perks.
    func getLTVPolicy() async throws -> LTVPolicy {
        try await get("/api/v1/tenant/ltv-policy", as: LTVPolicy.self)
    }

    /// `PATCH /tenant/ltv-policy` — update LTV tier thresholds and perks.
    @discardableResult
    func updateLTVPolicy(_ body: LTVPolicyPatch) async throws -> LTVPolicy {
        try await patch("/api/v1/tenant/ltv-policy", body: body, as: LTVPolicy.self)
    }
}
#endif
