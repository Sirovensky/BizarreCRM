import SwiftUI

// MARK: - ColorBlindSafePalette
// §26.6 — Color-blind-safe palette adjustments.
//
// WCAG SC 1.4.1: information conveyed by color alone must have a non-color
// alternative.  When the system flag
// `@Environment(\.accessibilityDifferentiateWithoutColor)` is `true`
// (set by iOS "Differentiate Without Color" under Settings → Accessibility →
// Display & Text Size) callers must add secondary cues — shapes, icons, or
// patterns — alongside any color-coded state.
//
// This file ships:
//  1. `ColorBlindSafeStatusModifier` — overlays an SF Symbol glyph on any
//     color-coded status indicator when the flag is set.
//  2. `ColorBlindSafeChartPatternModifier` — appends a dashed/dotted
//     pattern overlay to a chart series rectangle when the flag is set.
//  3. `View.colorBlindSafeStatus(...)` — convenience wrapper for (1).
//  4. `View.colorBlindSafeChartPattern(...)` — convenience wrapper for (2).
//
// **Usage — status badge:**
// ```swift
// Circle()
//     .fill(ticket.statusColor)
//     .frame(width: 10, height: 10)
//     .colorBlindSafeStatus(
//         systemImage: ticket.statusGlyph,   // e.g. "checkmark", "xmark"
//         accessibilityLabel: ticket.statusLabel
//     )
// ```
//
// **Usage — chart bar:**
// ```swift
// Rectangle()
//     .fill(series.color)
//     .colorBlindSafeChartPattern(pattern: series.pattern)
// ```

// MARK: - Status modifier

/// Overlays an SF Symbol glyph on a color-coded status view when
/// "Differentiate Without Color" is enabled.  Under the standard setting
/// this modifier is a no-op — no glyph is drawn, the color speaks for itself.
public struct ColorBlindSafeStatusModifier: ViewModifier {

    public let systemImage: String
    public let glyphColor: Color
    public let accessibilityLabel: String

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    public init(
        systemImage: String,
        glyphColor: Color = .primary,
        accessibilityLabel: String
    ) {
        self.systemImage = systemImage
        self.glyphColor = glyphColor
        self.accessibilityLabel = accessibilityLabel
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                if differentiate {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .foregroundStyle(glyphColor)
                        .accessibilityHidden(true) // semantic label already on parent
                }
            }
            .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Chart pattern modifier

/// Pattern options for color-blind-safe chart series.
public enum ChartPattern: String, Hashable, Sendable {
    /// Diagonal dashes (45°).
    case diagonal
    /// Horizontal dashes.
    case horizontal
    /// Dots.
    case dots
    /// Vertical dashes.
    case vertical
}

/// Overlays a dashed/dotted `Canvas` pattern on a chart bar or area when
/// "Differentiate Without Color" is enabled.  No-op under standard setting.
public struct ColorBlindSafeChartPatternModifier: ViewModifier {

    public let pattern: ChartPattern
    public let patternColor: Color
    public let lineWidth: CGFloat
    public let spacing: CGFloat

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    public init(
        pattern: ChartPattern = .diagonal,
        patternColor: Color = .primary,
        lineWidth: CGFloat = 1,
        spacing: CGFloat = 6
    ) {
        self.pattern = pattern
        self.patternColor = patternColor
        self.lineWidth = lineWidth
        self.spacing = spacing
    }

    public func body(content: Content) -> some View {
        content
            .overlay {
                if differentiate {
                    GeometryReader { proxy in
                        patternCanvas(size: proxy.size)
                            .opacity(0.5)
                            .allowsHitTesting(false)
                    }
                }
            }
    }

    // MARK: Private

    @ViewBuilder
    private func patternCanvas(size: CGSize) -> some View {
        Canvas { ctx, canvasSize in
            ctx.withCGContext { cgCtx in
                cgCtx.setStrokeColor(UIColor(patternColor).cgColor)
                cgCtx.setLineWidth(lineWidth)

                switch pattern {
                case .diagonal:
                    drawDiagonalLines(ctx: cgCtx, size: canvasSize, spacing: spacing)
                case .horizontal:
                    drawHorizontalLines(ctx: cgCtx, size: canvasSize, spacing: spacing)
                case .vertical:
                    drawVerticalLines(ctx: cgCtx, size: canvasSize, spacing: spacing)
                case .dots:
                    drawDots(ctx: cgCtx, size: canvasSize, spacing: spacing, lineWidth: lineWidth)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func drawDiagonalLines(ctx: CGContext, size: CGSize, spacing: CGFloat) {
        let count = Int((size.width + size.height) / spacing) + 2
        for i in 0 ..< count {
            let offset = CGFloat(i) * spacing
            ctx.move(to: CGPoint(x: offset - size.height, y: 0))
            ctx.addLine(to: CGPoint(x: offset, y: size.height))
        }
        ctx.strokePath()
    }

    private func drawHorizontalLines(ctx: CGContext, size: CGSize, spacing: CGFloat) {
        var y: CGFloat = spacing / 2
        while y < size.height {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        ctx.strokePath()
    }

    private func drawVerticalLines(ctx: CGContext, size: CGSize, spacing: CGFloat) {
        var x: CGFloat = spacing / 2
        while x < size.width {
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        ctx.strokePath()
    }

    private func drawDots(ctx: CGContext, size: CGSize, spacing: CGFloat, lineWidth: CGFloat) {
        let r = lineWidth
        var y: CGFloat = spacing / 2
        while y < size.height {
            var x: CGFloat = spacing / 2
            while x < size.width {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                x += spacing
            }
            y += spacing
        }
    }
}

// MARK: - View extensions

public extension View {
    /// Overlays an SF Symbol when "Differentiate Without Color" is enabled,
    /// adding a non-color cue alongside color-coded status indicators.
    ///
    /// - Parameters:
    ///   - systemImage: SF Symbol name (e.g. `"checkmark"`, `"xmark"`, `"exclamationmark"`).
    ///   - glyphColor: Foreground color for the glyph. Default `.primary`.
    ///   - accessibilityLabel: VoiceOver label for the full element.
    func colorBlindSafeStatus(
        systemImage: String,
        glyphColor: Color = .primary,
        accessibilityLabel: String
    ) -> some View {
        modifier(ColorBlindSafeStatusModifier(
            systemImage: systemImage,
            glyphColor: glyphColor,
            accessibilityLabel: accessibilityLabel
        ))
    }

    /// Overlays a pattern texture on a chart bar/area when
    /// "Differentiate Without Color" is enabled.
    ///
    /// - Parameters:
    ///   - pattern: Line pattern style. Default `.diagonal`.
    ///   - patternColor: Stroke color for the pattern. Default `.primary`.
    ///   - lineWidth: Stroke width. Default `1`.
    ///   - spacing: Gap between pattern lines or dots. Default `6`.
    func colorBlindSafeChartPattern(
        pattern: ChartPattern = .diagonal,
        patternColor: Color = .primary,
        lineWidth: CGFloat = 1,
        spacing: CGFloat = 6
    ) -> some View {
        modifier(ColorBlindSafeChartPatternModifier(
            pattern: pattern,
            patternColor: patternColor,
            lineWidth: lineWidth,
            spacing: spacing
        ))
    }
}
