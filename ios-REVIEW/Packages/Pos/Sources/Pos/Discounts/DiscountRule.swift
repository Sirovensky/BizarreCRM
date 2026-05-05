import Foundation

// MARK: - DiscountScope

/// Defines which cart elements a `DiscountRule` targets.
public enum DiscountScope: String, Codable, Sendable, Hashable, CaseIterable {
    /// Applied once to the entire cart subtotal.
    case whole
    /// Applied per matching cart line item.
    case lineItem
    /// Applied to every line whose item category matches `matcher`.
    case category
    /// Applied to every line whose SKU matches the `matcher` regex.
    case sku
}

// MARK: - DiscountChannel

/// Restricts which sales channel a `DiscountRule` may fire in.
///
/// - `any`: no restriction — fires in-store, online, and via payment links.
/// - `inStoreOnly`: fires only from the POS cart (never from a payment link or web checkout).
/// - `onlineOnly`: fires only from payment links / web checkout (never from POS).
public enum DiscountChannel: String, Codable, Sendable, Hashable, CaseIterable {
    /// No channel restriction — applies everywhere.
    case any
    /// Applies only when the sale originates from the POS register.
    case inStoreOnly = "in_store_only"
    /// Applies only when the sale originates from a payment link or web checkout.
    case onlineOnly  = "online_only"

    public var displayName: String {
        switch self {
        case .any:         return "Any channel"
        case .inStoreOnly: return "In-store (POS) only"
        case .onlineOnly:  return "Online / payment link only"
        }
    }
}

// MARK: - DiscountStackOrder

/// Controls the order in which discount types are applied when multiple rules
/// stack on the same cart element.
///
/// Default per-tenant is `.percentBeforeFixed` which matches the most common
/// accounting convention (apply the percentage first, then take dollars off
/// the reduced total, then compare with and without tax).
public enum DiscountStackOrder: String, Codable, Sendable, Hashable, CaseIterable {
    /// Percentage discounts are applied first, then fixed-amount discounts,
    /// then the result is compared against tax (default).
    case percentBeforeFixed = "percent_before_fixed"
    /// Fixed-amount discounts are deducted first, then percentages apply on
    /// the reduced basis.
    case fixedBeforePercent = "fixed_before_percent"

    public var displayName: String {
        switch self {
        case .percentBeforeFixed: return "% off first, then $ off"
        case .fixedBeforePercent: return "$ off first, then % off"
        }
    }
}

// MARK: - DiscountRule

/// A persistent, server-synced discount rule.
///
/// All money values use **cents** (Int) to avoid floating-point drift.
/// Percentages use `Double` 0.0–1.0 (e.g. 0.10 = 10 %).
///
/// Rules can restrict applicability via:
/// - `validFrom` / `validTo` date window
/// - `minQuantity` on a line
/// - `minCartTotalCents` cart threshold
/// - `maxUsesPerCustomer` per-customer cap (enforced server-side; iOS is optimistic)
///
/// `stackable = false` means this rule participates in the
/// "take best for customer" conflict resolution pass (see `DiscountEngine`).
/// `stackable = true` means it piles on top of every other stackable discount.
///
/// `managerApprovalRequired` blocks checkout until a `ManagerPinSheet` is
/// presented and approved.
public struct DiscountRule: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var name: String
    public var scope: DiscountScope
    /// Interpretation depends on `scope`:
    /// - `.whole` — ignored
    /// - `.lineItem` — ignored (applies to every line)
    /// - `.category` — exact category name match
    /// - `.sku` — regular-expression matched against `CartItem.sku`
    public var matcher: String
    /// Percentage discount 0.0–1.0.  Mutually exclusive with `discountFlatCents`.
    public var discountPercent: Double?
    /// Fixed discount in cents.  Mutually exclusive with `discountPercent`.
    /// Prefer `discountPercent` for percentage rules; use this for "$5 off" rules.
    public var discountFlatCents: Int?
    /// Minimum line quantity required for the rule to apply (`.lineItem` / `.sku`).
    public var minQuantity: Int?
    /// Minimum cart subtotal (cents) required for the rule to apply.
    public var minCartTotalCents: Int?
    /// Wall-clock window — rule is inert outside this window.
    public var validFrom: Date?
    public var validTo: Date?
    /// Server-enforced per-customer usage cap.  iOS shows a warning when
    /// the limit is reached (from the server error) but does NOT enforce locally.
    public var maxUsesPerCustomer: Int?
    /// When `false`, conflicts with other non-stackable rules are resolved by
    /// choosing the best discount for the customer.  When `true`, this rule
    /// stacks with any other stackable rules.
    public var stackable: Bool
    /// When `true`, cart checkout is blocked until a manager approves via
    /// `ManagerPinSheet`.
    public var managerApprovalRequired: Bool

    // MARK: - Eligibility gates (§16 discount types)

    /// When `true`, this rule only fires when the attached customer has never
    /// completed a sale at this tenant (first-time customer discount).
    ///
    /// The iOS side is *optimistic* — the server re-validates on checkout
    /// submission and rejects if the customer already has a prior order.
    public var firstTimeCustomerOnly: Bool

    /// Minimum loyalty tier name required for the rule to fire (e.g. `"Gold"`).
    /// `nil` = no loyalty-tier restriction.
    ///
    /// Checked against the customer's current membership tier; walk-in
    /// customers never match a non-nil tier requirement.
    public var requiredLoyaltyTier: String?

    /// Employee role slug required for the rule to fire (e.g. `"technician"`).
    /// `nil` = no role restriction (applies to all staff).
    ///
    /// Used for employee-discount rules — only cashiers whose role matches may
    /// apply the rule without manager override.
    public var requiredEmployeeRole: String?

    /// Set of category names **excluded** from this rule's scope.
    ///
    /// Even if the rule's `scope` would match a line (`.lineItem`, `.whole`),
    /// any line whose item category appears in this set is skipped.
    /// Empty set = no exclusions.
    public var excludedCategories: Set<String>

    /// Channel restriction — controls whether this rule fires in-store, online,
    /// or both.  Default `.any`.
    public var channel: DiscountChannel

    public init(
        id: String,
        name: String,
        scope: DiscountScope,
        matcher: String = "",
        discountPercent: Double? = nil,
        discountFlatCents: Int? = nil,
        minQuantity: Int? = nil,
        minCartTotalCents: Int? = nil,
        validFrom: Date? = nil,
        validTo: Date? = nil,
        maxUsesPerCustomer: Int? = nil,
        stackable: Bool = true,
        managerApprovalRequired: Bool = false,
        firstTimeCustomerOnly: Bool = false,
        requiredLoyaltyTier: String? = nil,
        requiredEmployeeRole: String? = nil,
        excludedCategories: Set<String> = [],
        channel: DiscountChannel = .any
    ) {
        self.id = id
        self.name = name
        self.scope = scope
        self.matcher = matcher
        self.discountPercent = discountPercent
        self.discountFlatCents = discountFlatCents
        self.minQuantity = minQuantity
        self.minCartTotalCents = minCartTotalCents
        self.validFrom = validFrom
        self.validTo = validTo
        self.maxUsesPerCustomer = maxUsesPerCustomer
        self.stackable = stackable
        self.managerApprovalRequired = managerApprovalRequired
        self.firstTimeCustomerOnly = firstTimeCustomerOnly
        self.requiredLoyaltyTier = requiredLoyaltyTier
        self.requiredEmployeeRole = requiredEmployeeRole
        self.excludedCategories = excludedCategories
        self.channel = channel
    }

    // MARK: - Custom Codable (new fields with backward-compatible defaults)

    private enum CodingKeys: String, CodingKey {
        case id, name, scope, matcher
        case discountPercent        = "discount_percent"
        case discountFlatCents      = "discount_flat_cents"
        case minQuantity            = "min_quantity"
        case minCartTotalCents      = "min_cart_total_cents"
        case validFrom              = "valid_from"
        case validTo                = "valid_to"
        case maxUsesPerCustomer     = "max_uses_per_customer"
        case stackable
        case managerApprovalRequired = "manager_approval_required"
        case firstTimeCustomerOnly  = "first_time_customer_only"
        case requiredLoyaltyTier    = "required_loyalty_tier"
        case requiredEmployeeRole   = "required_employee_role"
        case excludedCategories     = "excluded_categories"
        case channel
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                      = try c.decode(String.self,       forKey: .id)
        name                    = try c.decode(String.self,       forKey: .name)
        scope                   = try c.decode(DiscountScope.self, forKey: .scope)
        matcher                 = try c.decodeIfPresent(String.self, forKey: .matcher) ?? ""
        discountPercent         = try c.decodeIfPresent(Double.self, forKey: .discountPercent)
        discountFlatCents       = try c.decodeIfPresent(Int.self,   forKey: .discountFlatCents)
        minQuantity             = try c.decodeIfPresent(Int.self,   forKey: .minQuantity)
        minCartTotalCents       = try c.decodeIfPresent(Int.self,   forKey: .minCartTotalCents)
        validFrom               = try c.decodeIfPresent(Date.self,  forKey: .validFrom)
        validTo                 = try c.decodeIfPresent(Date.self,  forKey: .validTo)
        maxUsesPerCustomer      = try c.decodeIfPresent(Int.self,   forKey: .maxUsesPerCustomer)
        stackable               = try c.decodeIfPresent(Bool.self,  forKey: .stackable) ?? true
        managerApprovalRequired = try c.decodeIfPresent(Bool.self,  forKey: .managerApprovalRequired) ?? false
        firstTimeCustomerOnly   = try c.decodeIfPresent(Bool.self,  forKey: .firstTimeCustomerOnly) ?? false
        requiredLoyaltyTier     = try c.decodeIfPresent(String.self, forKey: .requiredLoyaltyTier)
        requiredEmployeeRole    = try c.decodeIfPresent(String.self, forKey: .requiredEmployeeRole)
        excludedCategories      = Set(try c.decodeIfPresent([String].self, forKey: .excludedCategories) ?? [])
        channel                 = try c.decodeIfPresent(DiscountChannel.self, forKey: .channel) ?? .any
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                        forKey: .id)
        try c.encode(name,                      forKey: .name)
        try c.encode(scope,                     forKey: .scope)
        try c.encode(matcher,                   forKey: .matcher)
        try c.encodeIfPresent(discountPercent,  forKey: .discountPercent)
        try c.encodeIfPresent(discountFlatCents, forKey: .discountFlatCents)
        try c.encodeIfPresent(minQuantity,       forKey: .minQuantity)
        try c.encodeIfPresent(minCartTotalCents, forKey: .minCartTotalCents)
        try c.encodeIfPresent(validFrom,         forKey: .validFrom)
        try c.encodeIfPresent(validTo,           forKey: .validTo)
        try c.encodeIfPresent(maxUsesPerCustomer, forKey: .maxUsesPerCustomer)
        try c.encode(stackable,                  forKey: .stackable)
        try c.encode(managerApprovalRequired,    forKey: .managerApprovalRequired)
        try c.encode(firstTimeCustomerOnly,      forKey: .firstTimeCustomerOnly)
        try c.encodeIfPresent(requiredLoyaltyTier, forKey: .requiredLoyaltyTier)
        try c.encodeIfPresent(requiredEmployeeRole, forKey: .requiredEmployeeRole)
        try c.encode(Array(excludedCategories),  forKey: .excludedCategories)
        try c.encode(channel,                    forKey: .channel)
    }

    // MARK: - Validity helpers

    /// Returns `true` when the rule is currently within its date window.
    public func isValid(at date: Date = .now) -> Bool {
        if let from = validFrom, date < from { return false }
        if let to = validTo, date > to { return false }
        return true
    }

    /// Computes the discount in cents to apply to a single `basis` amount.
    /// Returns 0 when neither `discountPercent` nor `discountFlatCents` is set.
    public func discountCents(forBasis basisCents: Int) -> Int {
        if let pct = discountPercent {
            return Int((Double(basisCents) * pct).rounded())
        }
        if let flat = discountFlatCents {
            return min(flat, basisCents) // never discount below 0
        }
        return 0
    }
}
