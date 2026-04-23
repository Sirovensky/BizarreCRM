import Foundation

/// §38 — Membership tier, subscription lifecycle, and customer membership endpoints.
///
/// Server routes (mounted at `/api/v1/membership`):
///   - `GET  /tiers`                        — list active tiers
///   - `POST /tiers`                        — create tier (admin)
///   - `PUT  /tiers/:id`                    — update tier (admin)
///   - `DELETE /tiers/:id`                  — soft-delete tier (admin)
///   - `GET  /customer/:customerId`         — get active subscription for customer
///   - `POST /subscribe`                    — enroll customer in a tier
///   - `POST /:id/cancel`                   — cancel subscription
///   - `POST /:id/pause`                    — pause subscription
///   - `POST /:id/resume`                   — resume subscription
///   - `GET  /:id/payments`                 — payment history
///   - `GET  /subscriptions`                — all active subscriptions (admin)
///   - `POST /enroll`                       — BlockChyp card enrollment
///   - `POST /payment-link`                 — generate payment link for signup

// MARK: - DTOs

/// A server membership tier row.
public struct MembershipTierDTO: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let slug: String?
    public let monthlyPrice: Double
    public let discountPct: Int
    public let discountAppliesTo: String?
    /// JSON-decoded array of benefit strings
    public let benefits: [String]
    public let color: String?
    public let sortOrder: Int
    public let isActive: Bool

    public init(
        id: Int,
        name: String,
        slug: String? = nil,
        monthlyPrice: Double,
        discountPct: Int = 0,
        discountAppliesTo: String? = "labor",
        benefits: [String] = [],
        color: String? = "#3b82f6",
        sortOrder: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.monthlyPrice = monthlyPrice
        self.discountPct = discountPct
        self.discountAppliesTo = discountAppliesTo
        self.benefits = benefits
        self.color = color
        self.sortOrder = sortOrder
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, benefits, color
        case monthlyPrice       = "monthly_price"
        case discountPct        = "discount_pct"
        case discountAppliesTo  = "discount_applies_to"
        case sortOrder          = "sort_order"
        case isActive           = "is_active"
    }
}

/// Active subscription for a customer, returned by `GET /membership/customer/:id`.
public struct CustomerSubscriptionDTO: Codable, Sendable, Identifiable {
    public let id: Int
    public let customerId: Int
    public let tierId: Int
    public let blockchypToken: String?
    public let status: String
    public let currentPeriodStart: String
    public let currentPeriodEnd: String
    public let cancelAtPeriodEnd: Bool
    public let pauseReason: String?
    public let signatureFile: String?
    public let lastChargeAt: String?
    public let lastChargeAmount: Double?
    public let createdAt: String?
    public let updatedAt: String?
    // Joined tier fields
    public let tierName: String?
    public let monthlyPrice: Double?
    public let discountPct: Int?
    public let discountAppliesTo: String?
    public let benefits: [String]?
    public let color: String?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId         = "customer_id"
        case tierId             = "tier_id"
        case blockchypToken     = "blockchyp_token"
        case status
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd   = "current_period_end"
        case cancelAtPeriodEnd  = "cancel_at_period_end"
        case pauseReason        = "pause_reason"
        case signatureFile      = "signature_file"
        case lastChargeAt       = "last_charge_at"
        case lastChargeAmount   = "last_charge_amount"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
        case tierName           = "tier_name"
        case monthlyPrice       = "monthly_price"
        case discountPct        = "discount_pct"
        case discountAppliesTo  = "discount_applies_to"
        case benefits
        case color
    }
}

/// Subscription payment record from `GET /membership/:id/payments`.
public struct SubscriptionPaymentDTO: Codable, Sendable, Identifiable {
    public let id: Int
    public let subscriptionId: Int
    public let amount: Double
    public let status: String
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case subscriptionId = "subscription_id"
        case amount
        case status
        case createdAt      = "created_at"
    }
}

/// Enroll request body for `POST /membership/subscribe`.
public struct MembershipSubscribeRequest: Encodable, Sendable {
    public let customerId: Int
    public let tierId: Int
    public let blockchypToken: String?

    public init(customerId: Int, tierId: Int, blockchypToken: String? = nil) {
        self.customerId = customerId
        self.tierId = tierId
        self.blockchypToken = blockchypToken
    }

    enum CodingKeys: String, CodingKey {
        case customerId     = "customer_id"
        case tierId         = "tier_id"
        case blockchypToken = "blockchyp_token"
    }
}

/// Cancel body for `POST /membership/:id/cancel`.
public struct MembershipCancelRequest: Encodable, Sendable {
    /// `true` = cancel now; `false` = cancel at period end.
    public let immediate: Bool

    public init(immediate: Bool = false) {
        self.immediate = immediate
    }
}

/// Pause body for `POST /membership/:id/pause`.
public struct MembershipPauseRequest: Encodable, Sendable {
    public let reason: String?
    public init(reason: String? = nil) { self.reason = reason }
}

/// Generic "action result" response for cancel/pause/resume.
public struct MembershipActionResultDTO: Decodable, Sendable {
    public let cancelled: Bool?
    public let paused: Bool?
    public let resumed: Bool?
    public let immediate: Bool?
}

/// Response from `POST /membership/enroll` (BlockChyp card enrollment).
public struct MembershipEnrollCardResultDTO: Decodable, Sendable {
    public let token: String
    public let maskedPan: String?
    public let cardType: String?

    enum CodingKeys: String, CodingKey {
        case token
        case maskedPan  = "maskedPan"
        case cardType   = "cardType"
    }
}

/// Response from `POST /membership/payment-link`.
public struct MembershipPaymentLinkDTO: Decodable, Sendable {
    public let linkUrl: String
    public let linkCode: String?
    public let tierName: String?
    public let amount: Double?

    enum CodingKeys: String, CodingKey {
        case linkUrl    = "linkUrl"
        case linkCode   = "linkCode"
        case tierName   = "tier_name"
        case amount
    }
}

/// Admin subscription row returned by `GET /membership/subscriptions`.
public struct AdminSubscriptionDTO: Codable, Sendable, Identifiable {
    public let id: Int
    public let customerId: Int
    public let tierId: Int
    public let status: String
    public let currentPeriodStart: String
    public let currentPeriodEnd: String
    public let tierName: String?
    public let monthlyPrice: Double?
    public let color: String?
    public let firstName: String?
    public let lastName: String?
    public let phone: String?
    public let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case customerId         = "customer_id"
        case tierId             = "tier_id"
        case status
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd   = "current_period_end"
        case tierName           = "tier_name"
        case monthlyPrice       = "monthly_price"
        case color
        case firstName          = "first_name"
        case lastName           = "last_name"
        case phone
        case email
    }
}

// MARK: - APIClient wrappers

public extension APIClient {

    // MARK: Tiers

    /// List all active membership tiers.
    /// `GET /membership/tiers`
    func listMembershipTiers() async throws -> [MembershipTierDTO] {
        try await get("/membership/tiers", as: [MembershipTierDTO].self)
    }

    // MARK: Customer subscription

    /// Fetch the active subscription for a customer (nil if none).
    /// `GET /membership/customer/:customerId`
    func getCustomerSubscription(customerId: Int) async throws -> CustomerSubscriptionDTO? {
        try await get("/membership/customer/\(customerId)", as: CustomerSubscriptionDTO?.self)
    }

    // MARK: Lifecycle

    /// Enroll a customer in a membership tier.
    /// `POST /membership/subscribe`
    func subscribeMembership(request: MembershipSubscribeRequest) async throws -> CustomerSubscriptionDTO {
        try await post("/membership/subscribe", body: request, as: CustomerSubscriptionDTO.self)
    }

    /// Cancel a subscription.
    /// `POST /membership/:id/cancel`
    func cancelMembership(id: Int, immediate: Bool = false) async throws -> MembershipActionResultDTO {
        try await post(
            "/membership/\(id)/cancel",
            body: MembershipCancelRequest(immediate: immediate),
            as: MembershipActionResultDTO.self
        )
    }

    /// Pause a subscription.
    /// `POST /membership/:id/pause`
    func pauseMembership(id: Int, reason: String? = nil) async throws -> MembershipActionResultDTO {
        try await post(
            "/membership/\(id)/pause",
            body: MembershipPauseRequest(reason: reason),
            as: MembershipActionResultDTO.self
        )
    }

    /// Resume a paused subscription.
    /// `POST /membership/:id/resume`
    func resumeMembership(id: Int) async throws -> MembershipActionResultDTO {
        try await post(
            "/membership/\(id)/resume",
            body: EmptyMembershipBody(),
            as: MembershipActionResultDTO.self
        )
    }

    // MARK: Payment history

    /// Get payment history for a subscription.
    /// `GET /membership/:id/payments`
    func getMembershipPayments(id: Int) async throws -> [SubscriptionPaymentDTO] {
        try await get("/membership/\(id)/payments", as: [SubscriptionPaymentDTO].self)
    }

    // MARK: Admin

    /// List all active subscriptions across all customers (admin).
    /// `GET /membership/subscriptions`
    func listAllSubscriptions() async throws -> [AdminSubscriptionDTO] {
        try await get("/membership/subscriptions", as: [AdminSubscriptionDTO].self)
    }

    /// Generate a BlockChyp payment link for remote membership signup.
    /// `POST /membership/payment-link`
    func createMembershipPaymentLink(tierId: Int, customerId: Int?) async throws -> MembershipPaymentLinkDTO {
        struct Body: Encodable, Sendable {
            let tierId: Int
            let customerId: Int?
            enum CodingKeys: String, CodingKey {
                case tierId = "tier_id"
                case customerId = "customer_id"
            }
        }
        return try await post(
            "/membership/payment-link",
            body: Body(tierId: tierId, customerId: customerId),
            as: MembershipPaymentLinkDTO.self
        )
    }
}

// MARK: - Private helpers

private struct EmptyMembershipBody: Encodable, Sendable {}
