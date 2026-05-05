import SwiftUI

// MARK: - DecorativeGradientModifier
// §91.13 — VoiceOver bypass for decorative gradients.
//
// Gradients used purely for visual polish (area-chart fills, card shimmer
// overlays, hero-tile chrome) carry no semantic information.  VoiceOver
// must skip them so the focus order stays clean and users don't hear "image"
// for every tinted background.
//
// This modifier is the single canonical way to mark a gradient (or any purely
// decorative shape/overlay) as presentation-only.  It sets:
//   • `accessibilityHidden(true)` — removes the view from the AX element tree.
//   • `allowsHitTesting(false)` — prevents the gradient from stealing taps
//     that should pass through to the content layer beneath it.
//
// **Usage — gradient fill on an area chart:**
// ```swift
// AreaMark(x: .value("Date", pt.date), y: .value("Revenue", pt.amount))
//     .foregroundStyle(
//         LinearGradient(colors: [.orange.opacity(0.35), .orange.opacity(0.05)],
//                        startPoint: .top, endPoint: .bottom)
//     )
//     // Swift Charts applies foreground styles via ChartContent, not a SwiftUI
//     // View modifier — hide the containing chart view instead:
// ```
// ```swift
// // For standalone overlay gradients use the modifier directly:
// LinearGradient(colors: [.white.opacity(0.08), .clear],
//                startPoint: .top, endPoint: .bottom)
//     .decorativeGradient()
// ```
//
// **Do NOT use this modifier** on gradients that encode data (e.g. a heatmap
// color scale bar where the gradient IS the information).  Those should keep
// their `accessibilityLabel`.

// MARK: - Modifier

public struct DecorativeGradientModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

// MARK: - View extension

public extension View {
    /// Marks this gradient (or any purely decorative overlay) as presentation-only.
    ///
    /// VoiceOver will skip the view entirely and taps pass through to underlying
    /// interactive content.  Use this on every gradient that does not convey data.
    func decorativeGradient() -> some View {
        modifier(DecorativeGradientModifier())
    }
}
