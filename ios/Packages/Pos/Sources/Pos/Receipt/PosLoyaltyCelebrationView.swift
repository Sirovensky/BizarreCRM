#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// §Agent-E — Post-sale loyalty celebration row. Rendered inside
/// `PosReceiptView` when `PosReceiptPayload.loyaltyDelta` is non-nil and > 0.
///
/// Shows:
/// - Star glow badge with the points earned + tier on the same headline line
///   e.g. "+55 pts earned · GOLD tier held"
/// - Progress bar with endpoint labels "GOLD 285 pts" / "PLATINUM 500 pts"
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

    /// Total loyalty points after this sale. Shown in the left bar label
    /// e.g. "GOLD 285 pts". When nil the left label shows the tier name only.
    public let pointsTotal: Int?

    /// Points threshold for the next tier. Shown in the right bar label
    /// e.g. "PLATINUM 500 pts". When nil the label shows "Next tier".
    public let nextTierPoints: Int?

    public init(
        pointsDelta: Int,
        tierBefore: String?,
        tierAfter: String?,
        tierProgress: Double = 0.5,
        pointsTotal: Int? = nil,
        nextTierPoints: Int? = nil
    ) {
        self.pointsDelta = pointsDelta
        self.tierBefore = tierBefore
        self.tierAfter = tierAfter
        self.tierProgress = max(0, min(1, tierProgress))
        self.pointsTotal = pointsTotal
        self.nextTierPoints = nextTierPoints
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
                    // Headline: "+55 pts earned · GOLD tier held"  (or "Welcome to PLATINUM!")
                    HStack(spacing: BrandSpacing.xs) {
                        Text(headlineText)
                            .font(.brandTitleSmall())
                            .foregroundStyle(.bizarreOrange)
                        if didTierUp {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.bizarreWarning)
                                .accessibilityHidden(true)
                        }
                    }
                    // Sub-line: total pts + pts to next tier
                    if let total = pointsTotal, let next = nextTierPoints {
                        let toNext = max(0, next - total)
                        let nextTierName = (didTierUp ? tierAfter : tierAfter) ?? "next tier"
                        Text("\(total) pts total · \(toNext) to \(nextTierName.uppercased())")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    } else if didTierUp, let after = tierAfter {
                        Text("Welcome to \(after)!")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                    } else if let tier = tierAfter ?? tierBefore {
                        Text(tier.uppercased())
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

    /// Combined headline. Matches mockup: "+55 pts earned · GOLD tier held"
    /// or "Welcome to PLATINUM!" on tier-up.
    private var headlineText: String {
        if didTierUp, let after = tierAfter {
            return "+\(pointsDelta) pts earned · Welcome to \(after.uppercased())!"
        }
        if let tier = tierAfter ?? tierBefore {
            return "+\(pointsDelta) pts earned · \(tier.uppercased()) tier held"
        }
        return "+\(pointsDelta) pts earned"
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
                Text(leftBarLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
                Text(rightBarLabel)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Bar endpoint labels

    /// Left label: "GOLD 285 pts" when pointsTotal is known, else "GOLD".
    private var leftBarLabel: String {
        let tier = (tierAfter ?? tierBefore)?.uppercased() ?? "—"
        if let total = pointsTotal {
            return "\(tier) \(total) pts"
        }
        return tier
    }

    /// Right label: "PLATINUM 500 pts" when nextTierPoints is known, else "NEXT TIER".
    private var rightBarLabel: String {
        let nextTier = (didTierUp ? tierAfter : tierAfter)?.uppercased() ?? "NEXT TIER"
        if let next = nextTierPoints {
            return "\(nextTier) \(next) pts"
        }
        return nextTier
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var parts: [String] = ["+\(pointsDelta) loyalty points earned"]
        if didTierUp, let after = tierAfter {
            parts.append("Tier upgrade to \(tierLabel(after))")
        } else if let tier = tierAfter ?? tierBefore {
            parts.append("Current tier: \(tierLabel(tier))")
        }
        return parts.joined(separator: ". ")
    }
}

#Preview {
    VStack(spacing: 16) {
        PosLoyaltyCelebrationView(
            pointsDelta: 55,
            tierBefore: "Gold",
            tierAfter: "Gold",
            tierProgress: 0.57,
            pointsTotal: 285,
            nextTierPoints: 500
        )
        PosLoyaltyCelebrationView(
            pointsDelta: 127,
            tierBefore: "Gold",
            tierAfter: "Platinum",
            tierProgress: 1.0,
            pointsTotal: 500,
            nextTierPoints: nil
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
