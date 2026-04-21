import Foundation

/// §38 — Tenant-configured loyalty earn/expiry rules.
///
/// All fields are value-type and immutable; mutate by constructing a new rule.
/// The `default` singleton provides sensible out-of-the-box settings for a
/// shop that hasn't customised the loyalty program yet.
///
/// Server contract: `GET /settings/loyalty/rule` → `LoyaltyRuleDTO`.
/// The iOS model is intentionally flat; complex server JSON is decoded via
/// `LoyaltyRuleDTO` in `MembershipsEndpoints.swift` and then mapped here.
public struct LoyaltyRule: Codable, Sendable, Equatable {

    // MARK: - Earn configuration

    /// Points awarded per whole dollar of spend.
    /// e.g. `1` → 1 pt per $1.
    public let pointsPerDollar: Int

    /// Multiplier applied on Tuesdays (or 1 for no bonus).
    public let tuesdayMultiplier: Int

    /// Bonus points awarded once on customer sign-up.
    public let signupBonusPoints: Int

    /// Multiplier applied on the customer's birthday (or 1 for no bonus).
    public let birthdayMultiplier: Int

    // MARK: - Expiry configuration

    /// Days after earn date that points expire.
    /// ≤ 0 means points never expire.
    public let expiryDays: Int

    // MARK: - Init

    public init(
        pointsPerDollar: Int = 1,
        tuesdayMultiplier: Int = 2,
        signupBonusPoints: Int = 100,
        birthdayMultiplier: Int = 3,
        expiryDays: Int = 365
    ) {
        self.pointsPerDollar = pointsPerDollar
        self.tuesdayMultiplier = tuesdayMultiplier
        self.signupBonusPoints = signupBonusPoints
        self.birthdayMultiplier = birthdayMultiplier
        self.expiryDays = expiryDays
    }

    // MARK: - Default

    /// Sensible out-of-box settings: 1 pt/$, 2× Tuesdays, 100 signup pts,
    /// 3× birthday, 365-day expiry.
    public static let `default` = LoyaltyRule()

    // MARK: - Codable keys (snake_case for server wire format)

    enum CodingKeys: String, CodingKey {
        case pointsPerDollar    = "points_per_dollar"
        case tuesdayMultiplier  = "tuesday_multiplier"
        case signupBonusPoints  = "signup_bonus_points"
        case birthdayMultiplier = "birthday_multiplier"
        case expiryDays         = "expiry_days"
    }
}

// MARK: - LoyaltyRedemptionRate

/// Configures how many cents a single loyalty point is worth at redemption.
///
/// Example: `centsPerPoint: 1` → 100 pts = $1.00.
/// Example: `centsPerPoint: 2` → 100 pts = $2.00.
public struct LoyaltyRedemptionRate: Codable, Sendable, Equatable {
    public let centsPerPoint: Int

    public init(centsPerPoint: Int = 1) {
        self.centsPerPoint = max(0, centsPerPoint)
    }

    public static let `default` = LoyaltyRedemptionRate(centsPerPoint: 1)

    enum CodingKeys: String, CodingKey {
        case centsPerPoint = "cents_per_point"
    }
}

// MARK: - LoyaltySale

/// Minimal sale descriptor passed to `LoyaltyCalculator.points(earned:rule:)`.
///
/// Kept in the Loyalty package so the calculator stays pure and dependency-free.
/// The POS layer constructs this from its `SaleRecord`.
public struct LoyaltySale: Sendable {
    /// Sale total in integer cents.
    public let amountCents: Int
    /// Date of sale — used for day-of-week multipliers.
    public let date: Date
    /// `true` when the sale occurs on the customer's birthday.
    public let isBirthday: Bool

    public init(amountCents: Int, date: Date = Date(), isBirthday: Bool = false) {
        self.amountCents = amountCents
        self.date = date
        self.isBirthday = isBirthday
    }
}

// MARK: - LoyaltyCart

/// Minimal cart descriptor for `MembershipPerkApplier`.
///
/// Only `subtotalCents` is needed for the discount calculation.
public struct LoyaltyCart: Sendable {
    public let subtotalCents: Int
    public init(subtotalCents: Int) {
        self.subtotalCents = subtotalCents
    }
}
