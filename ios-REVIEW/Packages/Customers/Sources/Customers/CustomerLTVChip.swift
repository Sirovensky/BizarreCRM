#if canImport(UIKit)
import SwiftUI
import DesignSystem

/// Pill displaying the customer's lifetime value.
/// Hides itself when `ltvCents` is nil or 0.
///
/// LTV is sourced from `CustomerAnalytics.lifetimeValue` (already in dollars).
/// The optional `ltvCents` overrides that when the server emits it in cents
/// directly on the detail response (future §44.2 server work).
public struct CustomerLTVChip: View {
    /// LTV in dollars (e.g. 1249.50). Pass `nil` to hide.
    public let ltvDollars: Double?

    public init(ltvDollars: Double?) {
        self.ltvDollars = ltvDollars
    }

    /// Convenience: construct from cents integer (e.g. Int64(124950) → $1,249.50).
    public init(ltvCents: Int64?) {
        if let cents = ltvCents, cents > 0 {
            ltvDollars = Double(cents) / 100.0
        } else {
            ltvDollars = nil
        }
    }

    public var body: some View {
        if let ltv = ltvDollars, ltv > 0 {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Text("LTV \(formatted(ltv))")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.sm)
            .background(Color.bizarreSurface2, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
            .accessibilityLabel("Lifetime value \(formatted(ltv))")
        }
    }

    private func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}
#endif
