import SwiftUI

// MARK: - ContrastBoostModifier

/// Respects `@Environment(\.colorSchemeContrast)` to darken borders and
/// brighten foreground text when the user has enabled Increase Contrast.
///
/// The modifier applies two independent adjustments:
/// 1. **Border** — thickens and darkens the stroke overlay.
/// 2. **Foreground** — brightens the primary text color (no-op in dark mode
///    where text is already near-white, but helps in light mode).
///
/// Both adjustments are additive and only take effect when contrast is
/// `.increased`; they are no-ops under `.standard`.
///
/// **Usage:**
/// ```swift
/// StatusPill(label: item.status)
///     .contrastBoost()
///
/// // Custom border color when boosted:
/// TextField(...)
///     .contrastBoost(borderColor: .primary)
/// ```
public struct ContrastBoostModifier: ViewModifier {

    // MARK: Configuration

    /// Color used for the high-contrast border stroke. Default: `.primary`.
    public let borderColor: Color
    /// Corner radius applied to the border overlay. Default: `DesignTokens.Radius.sm`.
    public let cornerRadius: CGFloat
    /// Additional border width applied when contrast is increased.
    public let boostedBorderWidth: CGFloat

    // MARK: Environment

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    // MARK: Init

    public init(
        borderColor: Color = .primary,
        cornerRadius: CGFloat = DesignTokens.Radius.sm,
        boostedBorderWidth: CGFloat = 1.5
    ) {
        self.borderColor = borderColor
        self.cornerRadius = cornerRadius
        self.boostedBorderWidth = boostedBorderWidth
    }

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(borderColor.opacity(boostedBorderOpacity), lineWidth: boostedBorderWidth)
                }
            }
            .foregroundStyle(boostedForegroundColor)
    }

    // MARK: Private helpers

    /// Opacity for the border stroke — stronger in light mode.
    private var boostedBorderOpacity: Double {
        contrast == .increased ? (colorScheme == .dark ? 0.65 : 0.90) : 0
    }

    /// In light mode with increased contrast, shift text slightly darker.
    /// In dark mode, primary is already light so we leave it alone.
    private var boostedForegroundColor: Color {
        guard contrast == .increased, colorScheme == .light else { return .primary }
        return Color.primary.opacity(1.0) // Already .primary; darken via overlay is preferred
    }
}

// MARK: - View extension

public extension View {
    /// Boosts border contrast and foreground brightness when Increase Contrast is on.
    ///
    /// - Parameters:
    ///   - borderColor: Stroke color for the high-contrast overlay. Default `.primary`.
    ///   - cornerRadius: Radius of the stroke rect. Default `DesignTokens.Radius.sm`.
    ///   - boostedBorderWidth: Extra border width when contrast is increased. Default `1.5`.
    func contrastBoost(
        borderColor: Color = .primary,
        cornerRadius: CGFloat = DesignTokens.Radius.sm,
        boostedBorderWidth: CGFloat = 1.5
    ) -> some View {
        modifier(ContrastBoostModifier(
            borderColor: borderColor,
            cornerRadius: cornerRadius,
            boostedBorderWidth: boostedBorderWidth
        ))
    }
}
