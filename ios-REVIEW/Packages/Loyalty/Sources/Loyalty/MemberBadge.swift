import SwiftUI
import DesignSystem

// MARK: - §38.1 Member badge on customer chips / POS

/// Compact loyalty tier badge for use on customer list rows, POS cart chips,
/// and any surface that needs a quick tier indicator.
///
/// Size variants:
///  - `.compact`  — icon only (16pt).  Use in list rows / chips.
///  - `.standard` — icon + tier name.  Use in detail headers / cards.
///  - `.prominent` — icon + tier name + "Member" label.  POS attach confirmation.
public struct MemberBadge: View {
    public enum Size: Sendable { case compact, standard, prominent }

    let tier: LoyaltyTier
    let size: Size

    public init(tier: LoyaltyTier, size: Size = .standard) {
        self.tier = tier
        self.size = size
    }

    /// Convenience initialiser: parse tier from raw string (safe, falls back to .bronze).
    public init(tierString: String, size: Size = .standard) {
        self.tier = LoyaltyTier.parse(tierString)
        self.size = size
    }

    public var body: some View {
        switch size {
        case .compact:
            Image(systemName: tier.systemSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tier.displayColor)
                .accessibilityLabel("\(tier.displayName) member")

        case .standard:
            HStack(spacing: 3) {
                Image(systemName: tier.systemSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tier.displayColor)
                    .accessibilityHidden(true)
                Text(tier.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(tier.displayColor)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 2)
            .background(tier.displayColor.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tier.displayName) loyalty member")

        case .prominent:
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: tier.systemSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tier.displayColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tier.displayName)
                        .font(.brandLabelLarge())
                        .foregroundStyle(tier.displayColor)
                    Text("Member")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .background(tier.displayColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tier.displayName) loyalty member")
        }
    }
}

// MARK: - Preview helper (consumed in tests)

extension MemberBadge {
    /// Returns true when the tier is above bronze (i.e. a "real" member with perks).
    public var isPaidTier: Bool { tier > .bronze }
}
