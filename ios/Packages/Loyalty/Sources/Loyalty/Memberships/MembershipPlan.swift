import Foundation

// MARK: - MembershipPerk

/// §38 — A single perk that a membership plan grants at checkout or in-app.
///
/// New cases can be added; existing cases must not be removed or reordered
/// (server JSON backward-compat).
public enum MembershipPerk: Codable, Sendable, Equatable {
    /// Percentage discount off the cart subtotal (0–100).
    case percentageDiscount(Int)
    /// Fixed discount in cents (always ≥ 0).
    case fixedDiscount(Int)
    /// One free service per billing period identified by `serviceId`.
    case freeService(serviceId: String, displayName: String)
    /// Exclusive access label — display-only, no POS enforcement.
    case exclusiveAccess(String)

    // MARK: - Codable (tagged union)

    private enum TypeKey: String, Codable {
        case percentageDiscount = "percentage_discount"
        case fixedDiscount      = "fixed_discount"
        case freeService        = "free_service"
        case exclusiveAccess    = "exclusive_access"
    }

    private enum CodingKeys: String, CodingKey {
        case type, value, serviceId = "service_id", displayName = "display_name", label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(TypeKey.self, forKey: .type)
        switch type {
        case .percentageDiscount:
            self = .percentageDiscount(try c.decode(Int.self, forKey: .value))
        case .fixedDiscount:
            self = .fixedDiscount(try c.decode(Int.self, forKey: .value))
        case .freeService:
            self = .freeService(
                serviceId: try c.decode(String.self, forKey: .serviceId),
                displayName: try c.decode(String.self, forKey: .displayName)
            )
        case .exclusiveAccess:
            self = .exclusiveAccess(try c.decode(String.self, forKey: .label))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .percentageDiscount(let v):
            try c.encode(TypeKey.percentageDiscount, forKey: .type)
            try c.encode(v, forKey: .value)
        case .fixedDiscount(let v):
            try c.encode(TypeKey.fixedDiscount, forKey: .type)
            try c.encode(v, forKey: .value)
        case .freeService(let sid, let name):
            try c.encode(TypeKey.freeService, forKey: .type)
            try c.encode(sid, forKey: .serviceId)
            try c.encode(name, forKey: .displayName)
        case .exclusiveAccess(let label):
            try c.encode(TypeKey.exclusiveAccess, forKey: .type)
            try c.encode(label, forKey: .label)
        }
    }

    // MARK: - Display

    public var displayName: String {
        switch self {
        case .percentageDiscount(let pct):
            return "\(pct)% off all services"
        case .fixedDiscount(let cents):
            let dollars = Double(cents) / 100.0
            return String(format: "$%.2f off cart", dollars)
        case .freeService(_, let name):
            return "Free \(name) per period"
        case .exclusiveAccess(let label):
            return label
        }
    }
}

// MARK: - MembershipPlan

/// §38 — Tenant-configured recurring membership plan.
///
/// Immutable value type. Admin edits create a new plan or update via the server.
/// PlanIDs are stable server UUIDs.
///
/// Server contract: `GET /memberships/plans` → `[MembershipPlan]`.
public struct MembershipPlan: Codable, Sendable, Identifiable, Equatable {

    public let id: String
    /// Human-readable plan name shown in admin + POS, e.g. "Gold Monthly".
    public let name: String
    /// Recurring charge in integer cents.
    public let pricePerPeriodCents: Int
    /// Billing cadence in days (30 = monthly, 365 = annual, 90 = quarterly).
    public let periodDays: Int
    /// Perks unlocked when a customer holds this plan at active status.
    public let perks: [MembershipPerk]
    /// One-time points awarded when the customer first enrolls in this plan.
    public let signupBonusPoints: Int

    public init(
        id: String,
        name: String,
        pricePerPeriodCents: Int,
        periodDays: Int,
        perks: [MembershipPerk],
        signupBonusPoints: Int = 0
    ) {
        self.id = id
        self.name = name
        self.pricePerPeriodCents = pricePerPeriodCents
        self.periodDays = periodDays
        self.perks = perks
        self.signupBonusPoints = signupBonusPoints
    }

    // MARK: - Derived

    /// Monthly equivalent price in cents for display purposes.
    public var monthlyPriceCents: Int {
        guard periodDays > 0 else { return pricePerPeriodCents }
        return Int(Double(pricePerPeriodCents) / Double(periodDays) * 30.0)
    }

    public var formattedPrice: String {
        let dollars = Double(pricePerPeriodCents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id, name, perks
        case pricePerPeriodCents = "price_per_period_cents"
        case periodDays          = "period_days"
        case signupBonusPoints   = "signup_bonus_points"
    }
}
