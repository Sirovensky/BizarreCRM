#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Circular badge showing the 0–100 health score in a tier colour.
///
/// Usage:
/// ```swift
/// CustomerHealthBadge(score: .init(value: 82, tier: .green, recommendation: nil))
/// ```
///
/// Glass is applied only when placed on navigation chrome per the iOS CLAUDE.md rule.
/// In the detail-view card context the badge uses a flat tinted background.
public struct CustomerHealthBadge: View {
    public let score: CustomerHealthScore

    public init(score: CustomerHealthScore) {
        self.score = score
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            ZStack {
                Circle()
                    .fill(tierColor.opacity(0.20))
                    .frame(width: 36, height: 36)

                Circle()
                    .strokeBorder(tierColor, lineWidth: 2)
                    .frame(width: 36, height: 36)

                Text("\(score.value)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(tierColor)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text("Health")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text(score.tier.displayLabel)
                    .font(.brandLabelLarge())
                    .foregroundStyle(tierColor)
            }
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .background(tierColor.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .strokeBorder(tierColor.opacity(0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Customer health score \(score.value) of 100. Tier \(score.tier.rawValue).")
    }

    private var tierColor: Color {
        switch score.tier {
        case .green:  return .bizarreSuccess
        case .yellow: return .bizarreWarning
        case .red:    return .bizarreError
        }
    }
}

// MARK: - CustomerHealthTier display helpers

extension CustomerHealthTier {
    fileprivate var displayLabel: String {
        switch self {
        case .green:  return "Healthy"
        case .yellow: return "At risk"
        case .red:    return "Critical"
        }
    }
}
#endif
