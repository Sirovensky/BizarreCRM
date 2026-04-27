import Foundation
import Networking

/// §38 §20 — APIClient extensions typed against Loyalty-package-local models.
///
/// These wrappers keep all `api.get/post/put/delete` calls inside
/// *Endpoints files (per §20 containment rule). Views and ViewModels
/// call these named methods rather than the raw HTTP verbs.
///
/// Server routes (confirmed against packages/server/src/routes/membership.routes.ts):
///   GET    /settings/loyalty/rule           — getLoyaltyRule()
///   PUT    /settings/loyalty/rule           — updateLoyaltyRule(_:)
///   DELETE /membership/tiers/:id            — deleteMembershipTier(id:)
///   PUT    /membership/tiers/:id            — updateMembershipTier(id:body:)
///   POST   /membership/tiers               — createMembershipTier(_:)

// MARK: - Request body (package-private)

private struct LoyaltyTierCreateOrUpdateRequest: Encodable, Sendable {
    let id: String
    let name: String
    let pricePerPeriodCents: Int
    let periodDays: Int
    let perks: [MembershipPerk]
    let signupBonusPoints: Int

    init(_ plan: MembershipPlan) {
        self.id = plan.id
        self.name = plan.name
        self.pricePerPeriodCents = plan.pricePerPeriodCents
        self.periodDays = plan.periodDays
        self.perks = plan.perks
        self.signupBonusPoints = plan.signupBonusPoints
    }

    enum CodingKeys: String, CodingKey {
        case id, name, perks
        case pricePerPeriodCents = "price_per_period_cents"
        case periodDays          = "period_days"
        case signupBonusPoints   = "signup_bonus_points"
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Loyalty rule

    /// `GET /settings/loyalty/rule` — fetch the tenant loyalty earn/expiry rule.
    func getLoyaltyRule() async throws -> LoyaltyRule {
        try await get("/settings/loyalty/rule", as: LoyaltyRule.self)
    }

    /// `PUT /settings/loyalty/rule` — persist changes to the earn/expiry rule.
    @discardableResult
    func updateLoyaltyRule(_ rule: LoyaltyRule) async throws -> LoyaltyRule {
        try await put("/settings/loyalty/rule", body: rule, as: LoyaltyRule.self)
    }

    // MARK: Membership tier CRUD

    /// `DELETE /membership/tiers/:id` — soft-delete a membership tier.
    func deleteMembershipTier(id: String) async throws {
        try await delete("/membership/tiers/\(id)")
    }

    /// `PUT /membership/tiers/:id` — update an existing membership tier.
    ///
    /// Maps the Networking `MembershipTierDTO` response into a `MembershipPlan`.
    func updateMembershipTier(id: String, plan: MembershipPlan) async throws -> MembershipPlan {
        let dto: MembershipTierDTO = try await put(
            "/membership/tiers/\(id)",
            body: LoyaltyTierCreateOrUpdateRequest(plan),
            as: MembershipTierDTO.self
        )
        return MembershipPlan(
            id: String(dto.id),
            name: dto.name,
            pricePerPeriodCents: Int(dto.monthlyPrice * 100),
            periodDays: 30,
            perks: dto.discountPct > 0 ? [.percentageDiscount(dto.discountPct)] : [],
            signupBonusPoints: 0
        )
    }

    /// `POST /membership/tiers` — create a new membership tier.
    ///
    /// Maps the Networking `MembershipTierDTO` response into a `MembershipPlan`.
    func createMembershipTier(_ plan: MembershipPlan) async throws -> MembershipPlan {
        let dto: MembershipTierDTO = try await post(
            "/membership/tiers",
            body: LoyaltyTierCreateOrUpdateRequest(plan),
            as: MembershipTierDTO.self
        )
        return MembershipPlan(
            id: String(dto.id),
            name: dto.name,
            pricePerPeriodCents: Int(dto.monthlyPrice * 100),
            periodDays: 30,
            perks: dto.discountPct > 0 ? [.percentageDiscount(dto.discountPct)] : [],
            signupBonusPoints: 0
        )
    }
}
