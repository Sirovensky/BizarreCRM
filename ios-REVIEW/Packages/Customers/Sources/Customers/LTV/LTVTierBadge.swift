#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - LTVTierBadge

/// §44.2 — Compact pill badge displaying the customer's LTV tier.
///
/// Rendered alongside `CustomerLTVChip` in the `CustomerDetailView` header.
/// Uses Liquid Glass on iOS 26+; falls back to `.ultraThinMaterial` earlier.
///
/// Accessibility: announces tier label + value so VoiceOver users get full context.
/// Reduce Motion: entry animation is suppressed when `accessibilityReduceMotion` is on.
public struct LTVTierBadge: View {
    public let tier: LTVTier
    /// Optional dollar value shown parenthetically (e.g. "$1 250").
    public let ltvDollars: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    public init(tier: LTVTier, ltvDollars: Double? = nil) {
        self.tier       = tier
        self.ltvDollars = ltvDollars
    }

    public var body: some View {
        HStack(spacing: BrandSpacing.xs) {
            Image(systemName: tier.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tier.color)
                .accessibilityHidden(true)

            Text(tier.label)
                .font(.brandLabelLarge())
                .foregroundStyle(tier.color)
        }
        .padding(.horizontal, BrandSpacing.md)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, in: Capsule(), tint: tier.color)
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: DesignTokens.Motion.snappy, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "LTV tier \(tier.label)"
        if let dollars = ltvDollars {
            let formatted = NumberFormatter.currencyNoDecimal.string(from: NSNumber(value: dollars)) ?? "$\(Int(dollars))"
            text += ", lifetime value \(formatted)"
        }
        return text
    }
}

private extension NumberFormatter {
    static let currencyNoDecimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()
}
#endif
