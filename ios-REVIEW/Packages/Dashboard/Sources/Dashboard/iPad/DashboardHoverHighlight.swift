import SwiftUI
import DesignSystem

// MARK: - DashboardHoverHighlight
//
// §22 iPad polish — hover-highlight modifier and numeric text-selection
// wrapper for Dashboard-specific views.
//
// This file builds on `DesignSystem.HoverHighlightModifier` (which wires
// `.hoverEffect(.highlight)` + pointer interaction). It adds a higher-level
// `DashboardNumericText` component that combines:
//   • `.textSelection(.enabled)` for copy on iPad (power-user affordance)
//   • `.monospacedDigit()` for stable layout as numbers change
//   • Brand font + foreground styling
//   • `brandHover()` on the cell container (delegated to call site)
//
// The DashboardHoverCard modifier wraps any card-shaped container in a
// hover-highlight region with the standard Dashboard card shape. It is
// intentionally a thin ViewModifier so it can be composed with existing
// card `.background` and `.overlay` styles already in the codebase.
//
// Immutability: both ViewModifier and View types are value-typed structs.

// MARK: - DashboardNumericText

/// Text view for a numeric KPI value with `.textSelection(.enabled)`,
/// `.monospacedDigit()`, and brand font built in.
///
/// Usage:
/// ```swift
/// DashboardNumericText("$4,200", font: .brandTitleLarge())
/// ```
public struct DashboardNumericText: View {
    private let value: String
    private let font: Font
    private let foregroundStyle: AnyShapeStyle

    public init(
        _ value: String,
        font: Font = .brandTitleLarge(),
        foregroundStyle: some ShapeStyle = Color.bizarreOnSurface
    ) {
        self.value = value
        self.font = font
        self.foregroundStyle = AnyShapeStyle(foregroundStyle)
    }

    public var body: some View {
        Text(value)
            .font(font)
            .foregroundStyle(foregroundStyle)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // §22 — allow copy on iPadOS for power users
            .textSelection(.enabled)
            .accessibilityValue(value)
    }
}

// MARK: - DashboardHoverCard modifier

/// Applies a hover-highlight region to a Dashboard card container.
///
/// Wraps the content in a `contentShape` so the full card rectangle
/// is hit-testable, then applies `.brandHover()`.
///
/// Usage:
/// ```swift
/// myCardView
///     .modifier(DashboardHoverCard(cornerRadius: 14))
/// ```
public struct DashboardHoverCard: ViewModifier {
    public let cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = DesignTokens.Radius.lg) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .brandHover()
    }
}

// MARK: - Convenience extension

public extension View {
    /// Apply Dashboard-standard hover-highlight to a card container.
    func dashboardHoverCard(cornerRadius: CGFloat = DesignTokens.Radius.lg) -> some View {
        modifier(DashboardHoverCard(cornerRadius: cornerRadius))
    }
}

// MARK: - DashboardHoverRow modifier

/// Applies a hover-highlight to a full-width list row in the Dashboard.
/// Uses `.contentShape(Rectangle())` so the entire row width is tappable.
///
/// Intended for rows inside `AttentionCard`, top-customer lists, etc.
///
/// Usage:
/// ```swift
/// myRowView
///     .modifier(DashboardHoverRow())
/// ```
public struct DashboardHoverRow: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .brandHover()
    }
}

public extension View {
    /// Apply Dashboard-standard hover-highlight to a row.
    func dashboardHoverRow() -> some View {
        modifier(DashboardHoverRow())
    }
}
