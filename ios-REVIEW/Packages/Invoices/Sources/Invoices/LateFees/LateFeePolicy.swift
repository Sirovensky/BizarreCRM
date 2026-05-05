import Foundation

// §7.12 Late Fee Policy

/// Tenant-configurable policy for applying late fees to overdue invoices.
/// All monetary values are in cents. Server applies the fee; client displays
/// the breakdown computed by `LateFeeCalculator`.
public struct LateFeePolicy: Codable, Sendable, Hashable {
    /// Fixed fee applied once after grace period expires (in cents).
    /// Mutually exclusive with `percentPerDay` in practice; both allowed by model.
    public let flatFeeCents: Int?
    /// Percentage of outstanding balance charged per overdue day (e.g. 0.05 = 0.05%).
    public let percentPerDay: Double?
    /// Days after the due date before any fee applies.
    public let gracePeriodDays: Int
    /// When true, the daily percent is applied to the running balance (including prior fees).
    public let compoundDaily: Bool
    /// Optional cap in cents. Fees will not exceed this value even if calculation exceeds it.
    public let maxFeeCents: Int?

    public init(
        flatFeeCents: Int? = nil,
        percentPerDay: Double? = nil,
        gracePeriodDays: Int = 0,
        compoundDaily: Bool = false,
        maxFeeCents: Int? = nil
    ) {
        self.flatFeeCents = flatFeeCents
        self.percentPerDay = percentPerDay
        self.gracePeriodDays = max(0, gracePeriodDays)
        self.compoundDaily = compoundDaily
        self.maxFeeCents = maxFeeCents
    }

    enum CodingKeys: String, CodingKey {
        case compoundDaily  = "compound_daily"
        case flatFeeCents   = "flat_fee_cents"
        case percentPerDay  = "percent_per_day"
        case gracePeriodDays = "grace_period_days"
        case maxFeeCents    = "max_fee_cents"
    }
}
