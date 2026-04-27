#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - PromotionWindowBannerView

/// Cashier-visible flash-sale banner that shows the promotion label and a live
/// countdown timer to the end of the promotion window.
///
/// Displayed in the POS cart chrome whenever at least one `.promotionWindow`
/// rule is live (`isPromotionLive(now:) == true`).
///
/// ## Design
/// - `.bizarreSurfaceElevated` pill, amber accent to distinguish from regular cart UI.
/// - Reduce Motion: countdown digits still update (informational); no animation.
/// - a11y: `accessibilityLabel` announces remaining minutes without seconds noise.
///
/// ## Usage
/// ```swift
/// if let promotion = activePricingRules.first(where: { $0.isPromotionLive() }) {
///     PromotionWindowBannerView(rule: promotion)
/// }
/// ```
public struct PromotionWindowBannerView: View {
    public let rule: PricingRule

    @State private var secondsRemaining: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(rule: PricingRule) {
        self.rule = rule
    }

    public var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.promotionLabel ?? rule.name)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)

                if secondsRemaining > 0 {
                    Text(countdownText)
                        .font(.brandLabelSmall().monospacedDigit())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }

            Spacer()

            if let pct = rule.promotionDiscountPercent, pct > 0 {
                Text(String(format: "−%.0f%%", pct * 100))
                    .font(.brandTitleMedium().monospacedDigit())
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(String(format: "%.0f%% off", pct * 100))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .fill(Color.bizarreSurfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                        .strokeBorder(Color.yellow.opacity(0.4), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .onAppear { updateCountdown() }
        .onReceive(timer) { _ in updateCountdown() }
    }

    // MARK: - Private helpers

    private var countdownText: String {
        let h = secondsRemaining / 3600
        let m = (secondsRemaining % 3600) / 60
        let s = secondsRemaining % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d remaining", h, m, s)
        } else {
            return String(format: "%d:%02d remaining", m, s)
        }
    }

    private var accessibilityLabel: String {
        let label = rule.promotionLabel ?? rule.name
        let minutesLeft = secondsRemaining / 60
        let suffix = minutesLeft > 0 ? ", \(minutesLeft) minute\(minutesLeft == 1 ? "" : "s") remaining" : ""
        return "\(label)\(suffix)"
    }

    private func updateCountdown() {
        let remaining = rule.promotionSecondsRemaining() ?? 0
        secondsRemaining = max(0, Int(remaining))
    }
}
#endif
