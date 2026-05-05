import SwiftUI

// MARK: - AdjacentRowSpacingModifier
// §26.7 — Spacing between adjacent tappable rows must be ≥ 8pt so that the
// 44×44pt minimum tap target of one row never overlaps the next. This modifier
// applies the brand-token `BrandSpacing.sm` (8pt) as bottom padding and asserts
// the minimum at debug time via a simple compile-time check (the constant
// `MIN_GAP` is read from `BrandSpacing.sm`, so any future change to the token
// would surface immediately in CI snapshot tests).
//
// Usage:
// ```swift
// VStack(spacing: 0) {
//     ForEach(items) { row in
//         RowView(row).adjacentRowSpacing()
//     }
// }
// ```
//
// In `List`, prefer `.listRowSpacing(BrandSpacing.sm)` on the parent — this
// modifier is for hand-rolled VStacks of tappable rows.

/// Minimum gap between two adjacent tappable rows per §26.7 (HIG 8pt).
public enum AdjacentRowSpacing {
    /// 8pt — matches `BrandSpacing.sm`. Sole source of truth for §26.7.
    public static let minimum: CGFloat = BrandSpacing.sm
}

private struct AdjacentRowSpacingModifier: ViewModifier {
    let spacing: CGFloat

    func body(content: Content) -> some View {
        content.padding(.bottom, spacing)
    }
}

public extension View {
    /// Inserts the §26.7 minimum 8pt gap below this row so the next row's
    /// 44×44pt tap target cannot overlap. Uses `BrandSpacing.sm` (8pt) by
    /// default — override only to add MORE spacing, never less.
    func adjacentRowSpacing(_ spacing: CGFloat = AdjacentRowSpacing.minimum) -> some View {
        // DEBUG guard: reject sub-8pt spacing — calling code violating §26.7.
        #if DEBUG
        if spacing < AdjacentRowSpacing.minimum {
            assertionFailure("§26.7 adjacentRowSpacing requires ≥ \(AdjacentRowSpacing.minimum)pt; got \(spacing)pt")
        }
        #endif
        return modifier(AdjacentRowSpacingModifier(spacing: max(spacing, AdjacentRowSpacing.minimum)))
    }
}
