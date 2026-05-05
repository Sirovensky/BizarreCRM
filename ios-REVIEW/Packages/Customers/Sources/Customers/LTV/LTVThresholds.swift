import Foundation

// MARK: - LTVThresholds

/// Tenant-configurable LTV tier thresholds (in cents).
/// Server can supply custom values via `GET /tenant/ltv-policy`.
/// Falls back to `LTVThresholds.default` when absent.
public struct LTVThresholds: Sendable, Equatable, Codable {
    /// Lower bound for silver (inclusive). Below → bronze.
    public let silverCents: Int
    /// Lower bound for gold (inclusive).
    public let goldCents: Int
    /// Lower bound for platinum (inclusive).
    public let platinumCents: Int

    public init(silverCents: Int, goldCents: Int, platinumCents: Int) {
        self.silverCents   = silverCents
        self.goldCents     = goldCents
        self.platinumCents = platinumCents
    }

    /// Default thresholds matching `LTVTier.thresholdCents`.
    public static let `default` = LTVThresholds(
        silverCents:   50_000,   // $500
        goldCents:     150_000,  // $1 500
        platinumCents: 500_000   // $5 000
    )

    enum CodingKeys: String, CodingKey {
        case silverCents   = "silver_cents"
        case goldCents     = "gold_cents"
        case platinumCents = "platinum_cents"
    }
}
