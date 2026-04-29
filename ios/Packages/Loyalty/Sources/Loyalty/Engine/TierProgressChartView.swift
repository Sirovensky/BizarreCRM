import SwiftUI
import DesignSystem

// MARK: - §38 Tier-progress chart

/// Horizontal segmented progress chart showing a customer's journey through
/// all four loyalty tiers.
///
/// Each segment represents one tier's spend band; the filled portion reflects
/// the customer's actual lifetime spend relative to each band's width.
///
/// Features:
/// - Four coloured segments (bronze → silver → gold → platinum).
/// - Animated fill on appear (respects Reduce Motion).
/// - Current tier callout label beneath the active segment.
/// - "Platinum – max tier" label when spend exceeds platinum threshold.
/// - Full VoiceOver description.
///
/// Example:
/// ```swift
/// TierProgressChartView(lifetimeSpendCents: 75_000) // $750 → silver band
/// ```
public struct TierProgressChartView: View {

    // MARK: - Inputs

    let lifetimeSpendCents: Int

    // MARK: - Init

    public init(lifetimeSpendCents: Int) {
        self.lifetimeSpendCents = lifetimeSpendCents
    }

    // MARK: - Constants

    /// Upper cap used to display the platinum band visually (spend above this is clamped).
    private static let displayCapCents: Int = 600_000 // $6,000

    private struct Band {
        let tier: LoyaltyTier
        let loCents: Int
        let hiCents: Int
        var widthCents: Int { hiCents - loCents }
    }

    private var bands: [Band] {
        [
            Band(tier: .bronze,   loCents: 0,       hiCents: 50_000),
            Band(tier: .silver,   loCents: 50_000,  hiCents: 100_000),
            Band(tier: .gold,     loCents: 100_000, hiCents: 500_000),
            Band(tier: .platinum, loCents: 500_000, hiCents: Self.displayCapCents)
        ]
    }

    private var currentTier: LoyaltyTier {
        LoyaltyCalculator.tier(for: lifetimeSpendCents)
    }

    // MARK: - Animation

    @State private var animationProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            chartBar
            legendRow
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .onAppear {
            if reduceMotion {
                animationProgress = 1
            } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.1)) {
                    animationProgress = 1
                }
            }
        }
    }

    // MARK: - Chart bar

    private var chartBar: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let totalRange = Double(Self.displayCapCents)
            let clampedSpend = min(lifetimeSpendCents, Self.displayCapCents)

            HStack(spacing: 2) {
                ForEach(bands, id: \.tier) { band in
                    let bandFraction = Double(band.widthCents) / totalRange
                    let bandWidth = totalWidth * bandFraction
                    let fillFraction = segmentFill(band: band, totalSpend: clampedSpend)
                    let animatedFill = fillFraction * animationProgress

                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(band.tier.displayColor.opacity(0.18))

                        // Fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(band.tier.displayColor)
                            .frame(width: bandWidth * animatedFill)
                    }
                    .frame(width: bandWidth, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .frame(height: 14)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 0) {
            ForEach(bands, id: \.tier) { band in
                let isActive = band.tier == currentTier
                VStack(alignment: .leading, spacing: 1) {
                    if isActive {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(band.tier.displayColor)
                            .accessibilityHidden(true)
                    }
                    Text(band.tier.displayName)
                        .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                        .foregroundStyle(isActive ? band.tier.displayColor : .bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Helpers

    /// Fraction of this band that is filled (0…1).
    private func segmentFill(band: Band, totalSpend: Int) -> Double {
        let lo = band.loCents
        let hi = band.hiCents
        if totalSpend <= lo { return 0 }
        if totalSpend >= hi { return 1 }
        return Double(totalSpend - lo) / Double(band.widthCents)
    }

    private var accessibilityLabel: String {
        let dollars = Double(lifetimeSpendCents) / 100
        let spend = String(format: "$%.0f", dollars)
        let tier = currentTier.displayName

        if currentTier == .platinum {
            return "Tier progress chart. Lifetime spend \(spend). \(tier) — maximum tier reached."
        }
        let tiers = LoyaltyTier.allCases
        if let idx = tiers.firstIndex(of: currentTier), idx + 1 < tiers.count {
            let nextTier = tiers[idx + 1]
            let nextThreshold = nextTier.minLifetimeSpendCents
            let remaining = max(0, nextThreshold - lifetimeSpendCents)
            let remainingDollars = String(format: "$%.0f", Double(remaining) / 100)
            return "Tier progress chart. Lifetime spend \(spend). Current tier: \(tier). \(remainingDollars) more to reach \(nextTier.displayName)."
        }
        return "Tier progress chart. Lifetime spend \(spend). Current tier: \(tier)."
    }
}
