import Foundation

// MARK: - CouponCode

/// A single coupon code record, as returned by the server and stored locally.
///
/// Ties a human-typed code string (e.g. `SAVE20`) to a `DiscountRule` on the
/// server. The iOS client is *optimistic*: it shows an applied discount before
/// server validation and reverts on error.
///
/// All usage counters are enforced server-side. The `usesRemaining` /
/// `perCustomerLimit` fields are only informational on iOS — they help the
/// cashier understand why a coupon was rejected.
public struct CouponCode: Codable, Sendable, Identifiable, Hashable {
    /// Stable server-assigned id. Used for de-dup + audit.
    public let id: String
    /// The human-facing code string (stored uppercased; UI auto-uppercases input).
    public let code: String
    /// Id of the `DiscountRule` this coupon activates.
    public let ruleId: String
    /// Human-readable name of the linked rule. Cached so we can show it
    /// before the rule object is available in the local store.
    public let ruleName: String
    /// Remaining global uses (`nil` = unlimited).
    public let usesRemaining: Int?
    /// Per-customer usage limit (`nil` = unlimited).
    public let perCustomerLimit: Int?
    /// UTC expiry timestamp (`nil` = never expires).
    public let expiresAt: Date?
    /// One-line description shown in the admin coupon list.
    public var description: String?

    public init(
        id: String,
        code: String,
        ruleId: String,
        ruleName: String,
        usesRemaining: Int? = nil,
        perCustomerLimit: Int? = nil,
        expiresAt: Date? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.code = code.uppercased()
        self.ruleId = ruleId
        self.ruleName = ruleName
        self.usesRemaining = usesRemaining
        self.perCustomerLimit = perCustomerLimit
        self.expiresAt = expiresAt
        self.description = description
    }

    // MARK: - Validity helpers

    /// Returns `true` when the coupon has not yet expired at the given time.
    public func isExpired(at now: Date = .now) -> Bool {
        guard let exp = expiresAt else { return false }
        return now > exp
    }

    /// Returns `true` when remaining uses are known and exhausted.
    public var isExhausted: Bool {
        guard let rem = usesRemaining else { return false }
        return rem <= 0
    }

    public var isActive: Bool {
        !isExpired() && !isExhausted
    }

    // MARK: - Codable keys (snake_case ↔ camelCase)

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case ruleId          = "rule_id"
        case ruleName        = "rule_name"
        case usesRemaining   = "uses_remaining"
        case perCustomerLimit = "per_customer_limit"
        case expiresAt       = "expires_at"
        case description
    }
}

// MARK: - CouponApplyRequest

/// Payload for `POST /coupons/apply`.
public struct CouponApplyRequest: Codable, Sendable {
    public let code: String
    public let cartId: String

    public init(code: String, cartId: String) {
        self.code = code
        self.cartId = cartId
    }

    enum CodingKeys: String, CodingKey {
        case code
        case cartId = "cart_id"
    }
}

// MARK: - CouponApplyResponse

/// Server response for `POST /coupons/apply`.
/// On success the server returns the validated coupon + the updated
/// discount amount to apply.
public struct CouponApplyResponse: Codable, Sendable {
    public let coupon: CouponCode
    /// Discount amount in cents authorised by this coupon for the current cart.
    public let discountCents: Int
    /// Human-readable confirmation message (e.g. "20% off applied!").
    public let message: String?

    enum CodingKeys: String, CodingKey {
        case coupon
        case discountCents = "discount_cents"
        case message
    }
}

// MARK: - BatchGenerateCouponsRequest

/// Payload for batch coupon generation (`POST /coupons/batch`).
public struct BatchGenerateCouponsRequest: Codable, Sendable {
    public let ruleId: String
    public let count: Int
    public let prefix: String?
    public let expiresAt: Date?
    public let usesPerCoupon: Int?
    public let perCustomerLimit: Int?

    public init(
        ruleId: String,
        count: Int,
        prefix: String? = nil,
        expiresAt: Date? = nil,
        usesPerCoupon: Int? = nil,
        perCustomerLimit: Int? = nil
    ) {
        self.ruleId = ruleId
        self.count = count
        self.prefix = prefix
        self.expiresAt = expiresAt
        self.usesPerCoupon = usesPerCoupon
        self.perCustomerLimit = perCustomerLimit
    }

    enum CodingKeys: String, CodingKey {
        case ruleId           = "rule_id"
        case count
        case prefix
        case expiresAt        = "expires_at"
        case usesPerCoupon    = "uses_per_coupon"
        case perCustomerLimit = "per_customer_limit"
    }
}
