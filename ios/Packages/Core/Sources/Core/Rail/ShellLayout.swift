import SwiftUI

// §22.G — ShellLayout: root iPad container.
//
// On iPad (.regular horizontal size class): renders the custom 64pt rail
// sidebar alongside a NavigationSplitView configured with
// `columnVisibility: .detailOnly`, so the system sidebar is suppressed and
// the rail owns all primary navigation.
//
// On iPhone (.compact horizontal size class): falls through to the caller-
// supplied `compactContent` closure which should be an existing TabView.
// Agent G does NOT touch App/RootView.swift — wiring is done by the
// orchestrator in a follow-up commit.

/// Container that gates between the custom iPad rail layout and the
/// existing iPhone `TabView` based on `horizontalSizeClass`.
///
/// Example:
/// ```swift
/// ShellLayout(selection: $destination) { dest in
///     switch dest {
///     case .dashboard: DashboardView()
///     // ...
///     }
/// } compactContent: {
///     MainTabView()
/// }
/// ```
@MainActor
public struct ShellLayout<Content: View, CompactContent: View>: View {

    @Binding private var selection: RailDestination
    @ViewBuilder private let content: (RailDestination) -> Content
    @ViewBuilder private let compactContent: () -> CompactContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        selection: Binding<RailDestination>,
        @ViewBuilder content: @escaping (RailDestination) -> Content,
        @ViewBuilder compactContent: @escaping () -> CompactContent
    ) {
        self._selection = selection
        self.content = content
        self.compactContent = compactContent
    }

    public var body: some View {
        // §22.4 — Slide Over / Split View: gate on actual container width
        // in addition to horizontalSizeClass. At 1/3 split or Slide Over
        // (~320–400 pt) the size class stays .regular on iPad but the
        // available width is too narrow for the 64 pt rail plus content.
        // Threshold 500 pt: at 1/2 split on 11" (~551 pt) we show rail;
        // at 1/3 split on 13" (~430 pt) we fall through to compact layout.
        GeometryReader { geo in
            if horizontalSizeClass == .regular && geo.size.width >= 500 {
                regularLayout
            } else {
                compactContent()
            }
        }
    }

    // MARK: - Regular (iPad) layout

    @ViewBuilder
    private var regularLayout: some View {
        // Plain HStack: custom 64pt rail on the left, feature content fills the
        // rest. The feature views supply their own `NavigationSplitView` (when
        // they need a list/detail split) — wrapping them in another NavSplit
        // here only added an empty toggleable ghost column on iOS 17+ because
        // `.detailOnly` is honoured loosely once the user taps the system
        // sidebar-toggle.
        // Custom rail sits beside the feature view. SwiftUI honours `.zIndex`
        // on HStack children for paint order, so the rail renders on top of
        // any animation overlay leaking out of the feature's own
        // `NavigationSplitView` sidebar (the "inner sidebar paving over rail
        // icons" bug from the screenshot walkthrough). It does not affect
        // layout — the rail stays leftmost, content fills the remainder.
        HStack(spacing: 0) {
            RailSidebarView(
                items: RailCatalog.primary,
                selection: $selection
            )
            .zIndex(1)

            Divider()
                .zIndex(1)

            content(selection)
        }
        // Don't ignore the top safe area — the iPad status bar (clock,
        // battery, wifi) is opaque chrome owned by the OS and content
        // sliding under it produces collisions like the repair-flow step
        // indicator overlapping the date/time row. Bottom edge stays
        // ignored so the rail glass extends to the home-indicator strip.
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

// MARK: - Convenience init when there is no compact fallback

extension ShellLayout where CompactContent == EmptyView {
    /// Initialise without a compact-layout closure.
    /// iPhone callers render nothing — use only when the host view
    /// already gates on `isRegular` before embedding `ShellLayout`.
    public init(
        selection: Binding<RailDestination>,
        @ViewBuilder content: @escaping (RailDestination) -> Content
    ) {
        self.init(
            selection: selection,
            content: content,
            compactContent: { EmptyView() }
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ShellLayout — iPad regular") {
    @Previewable @State var dest: RailDestination = .dashboard
    ShellLayout(selection: $dest) { destination in
        Text("Detail: \(destination.rawValue)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } compactContent: {
        Text("Compact / iPhone")
    }
}
#endif
