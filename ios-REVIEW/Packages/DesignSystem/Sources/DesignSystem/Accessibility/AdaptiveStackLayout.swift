import SwiftUI

// MARK: - AdaptiveStackLayout
// §26.2 — Dynamic-type XXXL ViewThatFits scaffolding.
//
// When the user's Dynamic Type size is in the accessibility range
// (AX1 – AX5, i.e. `isAccessibilitySize == true`) tabular / side-by-side
// layouts must reflow into vertical stacks so text never truncates and every
// label remains readable.
//
// `AdaptiveStack` wraps `ViewThatFits` to provide this reflow automatically:
// — by default it tries a horizontal `HStack` first;
// — if the content does not fit, it falls back to a `VStack`.
// Callers that want to skip the `ViewThatFits` probe and always go vertical at
// accessibility sizes can use `.adaptiveStack()` instead.
//
// **Usage — automatic reflow:**
// ```swift
// AdaptiveStack(spacing: DesignTokens.Spacing.sm) {
//     Text(item.label).font(.callout)
//     Spacer()
//     Text(item.value).font(.callout.monospacedDigit()
// }
// ```
//
// **Usage — manual environment gate:**
// ```swift
// Group {
//     if dynamicTypeSize.isAccessibilitySize {
//         VStack(alignment: .leading) { content() }
//     } else {
//         HStack { content() }
//     }
// }
// ```

// MARK: - AdaptiveStack

/// A layout container that switches from `HStack` to `VStack` when content
/// does not fit horizontally — covering the Dynamic Type XXXL (AX5) case.
///
/// Internally uses `ViewThatFits(in: .horizontal)` so the probe is free at
/// render time and incurs no extra layout passes in the common path.
public struct AdaptiveStack<Content: View>: View {

    // MARK: Configuration

    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let verticalAlignment: HorizontalAlignment
    private let content: () -> Content

    // MARK: Init

    /// - Parameters:
    ///   - alignment: Vertical alignment used when arranged horizontally. Default `.center`.
    ///   - spacing: Gap between children. Default `nil` (system default).
    ///   - verticalAlignment: Horizontal alignment used when arranged vertically. Default `.leading`.
    ///   - content: The child views — identical in both layout paths.
    public init(
        alignment: VerticalAlignment = .center,
        spacing: CGFloat? = nil,
        verticalAlignment: HorizontalAlignment = .leading,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.verticalAlignment = verticalAlignment
        self.content = content
    }

    // MARK: Body

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: alignment, spacing: spacing) {
                content()
            }
            VStack(alignment: verticalAlignment, spacing: spacing) {
                content()
            }
        }
    }
}

// MARK: - View extension

public extension View {
    /// Wraps this view in an `AdaptiveStack` container so it re-flows to a
    /// `VStack` when horizontal space is insufficient (e.g. Dynamic Type XXXL).
    ///
    /// Prefer `AdaptiveStack { ... }` when wrapping multiple siblings.
    /// Use this modifier when you want to reflow a single compound view.
    ///
    /// - Parameters:
    ///   - spacing: Gap between rows in vertical fallback. Default `nil`.
    ///   - verticalAlignment: Horizontal alignment when arranged vertically. Default `.leading`.
    func adaptiveStack(
        spacing: CGFloat? = nil,
        verticalAlignment: HorizontalAlignment = .leading
    ) -> some View {
        AdaptiveStack(spacing: spacing, verticalAlignment: verticalAlignment) {
            self
        }
    }
}
