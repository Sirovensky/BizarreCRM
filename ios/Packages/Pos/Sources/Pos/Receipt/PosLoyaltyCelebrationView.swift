#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Post-sale loyalty celebration row. Rendered inside
/// `PosReceiptView` when `PosReceiptPayload.loyaltyDelta` is non-nil and > 0.
///
/// Shows:
/// - Star glow badge with the points earned
/// - Tier progress bar (before → after)
/// - "+N pts earned" label
/// - Optional tier-up crown when `tierBefore != tierAfter`
///
/// Hidden entirely when the payload has no loyalty data.
public struct PosLoyaltyCelebrationView: View {
    public let pointsDelta: Int
    public let tierBefore: String?
    public let tierAfter: String?

    /// Fraction 0…1 progress toward next tier. Caller computes from the
    /// loyalty account; defaults to 0.5 for preview.
    public let tierProgress: Double

    public init(
        pointsDelta: Int,
        tierBefore: String?,
        tierAfter: String?,
        tierProgress: Double = 0.5
    ) {
        self.pointsDelta = pointsDelta
        self.tierBefore = tierBefore
        self.tierAfter = tierAfter
        self.tierProgress = max(0, min(1, tierProgress))
    }

    private var didTierUp: Bool {
        guard let before = tierBefore, let after = tierAfter else { return false }
        return before.caseInsensitiveCompare(after) != .orderedSame
    }

    public var body: some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.sm) {
                starGlow
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    HStack(spacing: BrandSpacing.xs) {
                        // Mockup line 2217: "+55 pts earned · GOLD tier held"
                        Text(pointsLabel)
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOnSurface)
                        if didTierUp {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.bizarreWarning)
                                .accessibilityHidden(true)
                        }
                    }
                    if didTierUp, let after = tierAfter {
                        Text("Welcome to \(after)!")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    } else if let tier = tierAfter ?? tierBefore {
                        Text(tier)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer(minLength: 0)
            }

            tierProgressBar
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.md)
        .background(Color.bizarreSurface1.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bizarreWarning.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Sub-views

    private var starGlow: some View {
        ZStack {
            Circle()
                .fill(Color.bizarreWarning.opacity(0.15))
                .frame(width: 44, height: 44)
            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.bizarreWarning)
        }
        .accessibilityHidden(true)
    }

    private var tierProgressBar: some View {
        VStack(spacing: BrandSpacing.xxs) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.bizarreOutline.opacity(0.3))
                    Capsule()
                        .fill(Color.bizarreWarning)
                        .frame(width: proxy.size.width * tierProgress)
                }
            }
            .frame(height: 6)

            // Tier label row — matches mockup "GOLD 285 pts" / "PLATINUM 500 pts"
            HStack {
                Text(tierBefore?.uppercased() ?? "—")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text((didTierUp ? tierAfter : (tierAfter.flatMap { "Next: \($0)" } ?? "Next tier"))?.uppercased() ?? "NEXT TIER")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Helpers

    /// Mockup label format: "+55 pts earned · GOLD tier held" /
    /// "+120 pts earned · PLATINUM tier up". The trailing tier suffix
    /// is dropped when no tier info is available.
    private var pointsLabel: String {
        let base = "+\(pointsDelta) pts earned"
        guard let tier = (tierAfter ?? tierBefore), !tier.isEmpty else { return base }
        let upOrHeld = didTierUp ? "up" : "held"
        return "\(base) · \(tier.uppercased()) tier \(upOrHeld)"
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = ["+\(pointsDelta) loyalty points earned"]
        if didTierUp, let after = tierAfter {
            parts.append("Tier upgrade to \(after)")
        } else if let tier = tierAfter ?? tierBefore {
            parts.append("Current tier: \(tier)")
        }
        return parts.joined(separator: ". ")
    }
}

#Preview {
    VStack(spacing: 16) {
        PosLoyaltyCelebrationView(
            pointsDelta: 127,
            tierBefore: "Gold",
            tierAfter: "Platinum",
            tierProgress: 1.0
        )
        PosLoyaltyCelebrationView(
            pointsDelta: 45,
            tierBefore: "Silver",
            tierAfter: "Silver",
            tierProgress: 0.57
        )
    }
    .padding()
    .background(Color.bizarreSurfaceBase)
    .preferredColorScheme(.dark)
}
#endif
