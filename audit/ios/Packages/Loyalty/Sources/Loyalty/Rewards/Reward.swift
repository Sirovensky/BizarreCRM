import Foundation

/// §38 — A single redeemable reward in the Loyalty Rewards Catalog.
///
/// All properties are immutable value-type; create new instances rather than mutating.
/// `tierRequirement` is optional — `nil` means any tier can redeem.
///
/// The `id` is a stable, URL-safe string slug (e.g. "free-wash") so the rewards
/// catalog can be seeded client-side without a database ID, and custom additions
/// can carry merchant-assigned identifiers.
public struct Reward: Identifiable, Hashable, Sendable {

    // MARK: - Identity

    /// Stable slug-like identifier (e.g. "free-wash", "10-off-next-visit").
    public let id: String

    // MARK: - Display

    /// Short title shown in the catalog row / grid cell.
    public let title: String

    /// Longer description explaining the reward.
    public let description: String

    /// SF Symbol name used as the reward icon when no remote image is available.
    public let imageName: String

    // MARK: - Redemption

    /// Points cost the customer must have (and will spend) to redeem.
    public let pointsCost: Int

    // MARK: - Gating

    /// Minimum loyalty tier required to unlock this reward.
    /// `nil` — available to all tiers. Non-nil — customer's tier must be ≥ this value.
    public let tierRequirement: LoyaltyTier?

    // MARK: - Init

    public init(
        id: String,
        title: String,
        description: String,
        imageName: String,
        pointsCost: Int,
        tierRequirement: LoyaltyTier? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.imageName = imageName
        self.pointsCost = pointsCost
        self.tierRequirement = tierRequirement
    }

    // MARK: - Eligibility

    /// Returns `true` when the customer meets both the tier gate AND has sufficient points.
    ///
    /// - Parameters:
    ///   - tier: Customer's current loyalty tier.
    ///   - availablePoints: Customer's current redeemable point balance.
    public func isEligible(tier: LoyaltyTier, availablePoints: Int) -> Bool {
        let tierOK: Bool
        if let required = tierRequirement {
            tierOK = tier >= required
        } else {
            tierOK = true
        }
        return tierOK && availablePoints >= pointsCost
    }
}
