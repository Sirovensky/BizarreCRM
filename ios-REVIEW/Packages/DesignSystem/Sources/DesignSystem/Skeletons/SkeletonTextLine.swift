import SwiftUI

// MARK: - SkeletonTextLine

/// A single-line text placeholder with configurable relative width.
///
/// Widths are expressed as a fraction of the available width (0...1),
/// making layouts responsive without hardcoded point values.
///
/// ```swift
/// VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
///     SkeletonTextLine(widthFraction: 0.75)   // title — 75 % wide
///     SkeletonTextLine(widthFraction: 0.50, lineHeight: 11)  // subtitle
/// }
/// ```
public struct SkeletonTextLine: View {

    // MARK: - Constants

    /// Default line height that matches typical body text.
    public static let defaultLineHeight: CGFloat = 14
    /// Minimum allowed width fraction (avoids zero-width views).
    public static let minimumWidthFraction: CGFloat = 0.05
    /// Maximum allowed width fraction (full-width bar).
    public static let maximumWidthFraction: CGFloat = 1.0

    // MARK: - Stored properties

    /// Fraction of available width, clamped to `minimumWidthFraction...maximumWidthFraction`.
    public let widthFraction: CGFloat
    /// Height of the simulated text line.
    public let lineHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Init

    /// - Parameters:
    ///   - widthFraction: Proportion of the available width (0.05...1.0). Default `1.0`.
    ///   - lineHeight: Height of the placeholder bar. Default `14`.
    public init(widthFraction: CGFloat = 1.0, lineHeight: CGFloat = defaultLineHeight) {
        self.widthFraction = widthFraction.clamped(to: Self.minimumWidthFraction ... Self.maximumWidthFraction)
        self.lineHeight = max(1, lineHeight)
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { proxy in
            let barWidth = proxy.size.width * widthFraction
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs)
                .fill(Color.primary.opacity(SkeletonShape.baseFillOpacity))
                .frame(width: barWidth, height: lineHeight)
                .overlay {
                    if !reduceMotion {
                        SkeletonShimmerOverlay(
                            highlightOpacity: SkeletonShape.shimmerHighlightOpacity,
                            duration: SkeletonShape.shimmerDuration
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                    }
                }
        }
        .frame(height: lineHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Comparable + Comparable extensions

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
