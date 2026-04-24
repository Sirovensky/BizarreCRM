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

    // NavigationSplitView column visibility — keep detail-only so system
    // sidebar stays suppressed; the rail owns primary navigation.
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

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
        if horizontalSizeClass == .regular {
            regularLayout
        } else {
            compactContent()
        }
    }

    // MARK: - Regular (iPad) layout

    @ViewBuilder
    private var regularLayout: some View {
        HStack(spacing: 0) {
            RailSidebarView(
                items: RailCatalog.primary,
                selection: $selection
            )

            Divider()

            // NavigationSplitView with .detailOnly suppresses the system
            // sidebar column, giving the custom rail full nav ownership.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Sidebar column is intentionally empty — the rail above
                // handles primary navigation. Detail column carries content.
                EmptyView()
            } detail: {
                content(selection)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
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
