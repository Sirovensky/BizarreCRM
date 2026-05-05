import SwiftUI
import DesignSystem

// MARK: - §38 Redemption catalog row

/// A single tappable row in the rewards redemption catalog.
///
/// Shows:
/// - SF Symbol icon (from `reward.imageName`) in a coloured capsule.
/// - Title + description (truncated to 2 lines).
/// - Points cost badge on the trailing edge.
/// - Tier-lock indicator when the customer does not meet the tier gate.
/// - Dimmed + disabled appearance when the customer lacks points or tier.
///
/// Usage:
/// ```swift
/// List(rewards) { reward in
///     RewardCatalogRow(reward: reward, customerTier: .silver, availablePoints: 420) {
///         viewModel.redeem(reward)
///     }
/// }
/// ```
public struct RewardCatalogRow: View {

    // MARK: - Inputs

    let reward: Reward
    let customerTier: LoyaltyTier
    let availablePoints: Int
    let onRedeem: () -> Void

    // MARK: - Init

    public init(
        reward: Reward,
        customerTier: LoyaltyTier,
        availablePoints: Int,
        onRedeem: @escaping () -> Void
    ) {
        self.reward = reward
        self.customerTier = customerTier
        self.availablePoints = availablePoints
        self.onRedeem = onRedeem
    }

    // MARK: - Derived state

    private var eligible: Bool {
        reward.isEligible(tier: customerTier, availablePoints: availablePoints)
    }

    private var tierLocked: Bool {
        if let required = reward.tierRequirement {
            return customerTier < required
        }
        return false
    }

    // MARK: - Body

    public var body: some View {
        Button(action: onRedeem) {
            HStack(spacing: BrandSpacing.md) {
                iconView
                infoStack
                Spacer(minLength: BrandSpacing.xs)
                trailingBadge
            }
            .padding(.vertical, BrandSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!eligible)
        .opacity(eligible ? 1.0 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(eligible ? "Double-tap to redeem this reward" : "")
        .accessibilityAddTraits(eligible ? [] : .isStaticText)
    }

    // MARK: - Subviews

    private var iconView: some View {
        Image(systemName: reward.imageName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(eligible ? .bizarreOrange : .bizarreOnSurfaceMuted)
            .frame(width: 40, height: 40)
            .background(
                (eligible ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted).opacity(0.12),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
            )
            .accessibilityHidden(true)
    }

    private var infoStack: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text(reward.title)
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .lineLimit(1)

            Text(reward.description)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(2)

            if tierLocked, let required = reward.tierRequirement {
                Label("\(required.displayName) required", systemImage: "lock.fill")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("\(required.displayName) tier required to unlock")
            }
        }
    }

    private var trailingBadge: some View {
        VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
            Text("\(reward.pointsCost.formatted(.number))")
                .font(.brandMono(size: 16))
                .foregroundStyle(eligible ? .bizarreOrange : .bizarreOnSurfaceMuted)
            Text("pts")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xs)
        .background(
            (eligible ? Color.bizarreOrange : Color.bizarreSurface2).opacity(0.12),
            in: Capsule()
        )
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts = ["\(reward.title). \(reward.pointsCost) points."]
        if tierLocked, let required = reward.tierRequirement {
            parts.append("Requires \(required.displayName) tier.")
        } else if !eligible {
            parts.append("Insufficient points.")
        }
        return parts.joined(separator: " ")
    }
}
