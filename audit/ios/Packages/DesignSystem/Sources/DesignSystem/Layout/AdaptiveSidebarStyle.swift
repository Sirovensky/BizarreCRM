import SwiftUI

// §22.1 — Sidebar: pinned on 13" iPad, collapsible on 11", with the
// canonical `.navigationSplitViewStyle(.balanced)` style applied.
//
// SwiftUI's `NavigationSplitView` initial column visibility depends on
// the available width.  This modifier inspects the horizontal size class
// and the scene size to decide whether the sidebar should be pinned
// (`.all`) or collapsed to the content+detail pair (`.doubleColumn`).
//
// Usage:
//   NavigationSplitView(columnVisibility: $columnVisibility) {
//       Sidebar()
//   } content: {
//       List()
//   } detail: {
//       Detail()
//   }
//   .brandAdaptiveSidebar(visibility: $columnVisibility)

// MARK: - Breakpoints

/// Width breakpoints used by `BrandAdaptiveSidebarModifier` (§22.1).
public enum AdaptiveSidebarBreakpoints {
    /// Below this width the sidebar collapses to a rail/double-column.
    /// 1180 pt is roughly the 13" iPad portrait width and the 11" iPad
    /// landscape width — the canonical "compact-ish iPad" boundary.
    public static let pinnedMinWidth: CGFloat = 1180
}

// MARK: - BrandAdaptiveSidebarModifier

/// Drives `columnVisibility` of an enclosing `NavigationSplitView` based on
/// the current width and applies the brand-standard `.balanced` style.
///
/// - On widths ≥ `AdaptiveSidebarBreakpoints.pinnedMinWidth` (13" iPad
///   landscape) the sidebar is pinned (`.all`).
/// - On smaller widths (11" iPad, portrait, Stage Manager) it collapses
///   to `.doubleColumn` so the user can swipe / tap to reveal it.
/// - On compact horizontal size class the binding is left untouched so
///   SwiftUI's stack-collapsed behaviour takes over.
public struct BrandAdaptiveSidebarModifier: ViewModifier {

    @Binding private var visibility: NavigationSplitViewVisibility
    @Environment(\.horizontalSizeClass) private var hSize

    public init(visibility: Binding<NavigationSplitViewVisibility>) {
        self._visibility = visibility
    }

    public func body(content: Content) -> some View {
        content
            .navigationSplitViewStyle(.balanced)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { apply(width: geo.size.width) }
                        .onChange(of: geo.size.width) { _, new in apply(width: new) }
                }
            )
    }

    private func apply(width: CGFloat) {
        guard hSize == .regular else { return }
        let target: NavigationSplitViewVisibility =
            width >= AdaptiveSidebarBreakpoints.pinnedMinWidth ? .all : .doubleColumn
        if visibility != target {
            visibility = target
        }
    }
}

// MARK: - View extension

public extension View {

    /// Applies §22.1 sidebar policy: pinned (`.all`) on 13" iPad, collapsible
    /// (`.doubleColumn`) on 11" / portrait, plus `.navigationSplitViewStyle(.balanced)`.
    ///
    /// - Parameter visibility: Binding to the column-visibility state used
    ///   by the enclosing `NavigationSplitView`.
    /// - Returns: A view that adjusts the binding when the available width
    ///   crosses the pinned/collapsed breakpoint.
    func brandAdaptiveSidebar(
        visibility: Binding<NavigationSplitViewVisibility>
    ) -> some View {
        modifier(BrandAdaptiveSidebarModifier(visibility: visibility))
    }
}
