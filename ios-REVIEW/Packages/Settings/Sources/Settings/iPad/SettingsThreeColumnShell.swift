import SwiftUI
import Core
import DesignSystem

// MARK: - SettingsThreeColumnShell

/// iPad-first orchestrator for the Settings root.
///
/// Renders a `NavigationSplitView` with three columns:
/// - Col 1 (`SettingsSectionSidebar`) — grouped sections
/// - Col 2 — page list for the selected section, or `SettingsSearchResultsPane`
///            when search is active
/// - Col 3 — the selected page detail view
///
/// Keyboard shortcuts (⌘F, ⌘W, Escape) are wired via
/// `SettingsKeyboardShortcutsModifier`.  Liquid Glass chrome on all navigation
/// bars.
///
/// ## Usage
/// ```swift
/// SettingsThreeColumnShell(detailView: { pageID in
///     myPageRouter(pageID)
/// }, isAdmin: session.isAdmin)
/// ```
public struct SettingsThreeColumnShell<Detail: View>: View {

    // MARK: - Configuration

    let isAdmin: Bool

    /// Caller-supplied factory that turns a page ID string into a detail view.
    let detailView: (String) -> Detail

    // MARK: - State

    @State private var selectedSectionID: String? = nil
    @State private var selectedPageID: String? = nil
    @State private var isSearchActive: Bool = false
    @State private var searchVM = SettingsSearchViewModel()

    @FocusState private var searchFieldFocused: Bool

    // MARK: - Derived

    private var sections: [SettingsSection] {
        SettingsSectionGroups.sections(includeAdmin: isAdmin)
    }

    private var selectedSection: SettingsSection? {
        guard let id = selectedSectionID else { return nil }
        return sections.first { $0.id == id }
    }

    // MARK: - Init

    public init(
        isAdmin: Bool = false,
        @ViewBuilder detailView: @escaping (String) -> Detail
    ) {
        self.isAdmin = isAdmin
        self.detailView = detailView
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Column 1 — section sidebar
            SettingsSectionSidebar(
                sections: sections,
                selectedSectionID: $selectedSectionID,
                isSearchActive: isSearchActive
            )
        } content: {
            // Column 2 — page list or search pane
            if isSearchActive {
                SettingsSearchResultsPane(
                    vm: searchVM,
                    onSelect: handleSearchSelect,
                    isFieldFocused: $searchFieldFocused
                )
                .navigationTitle("Search")
            } else {
                pageListContent
            }
        } detail: {
            // Column 3 — detail view
            NavigationStack {
                if let pageID = selectedPageID {
                    detailView(pageID)
                } else {
                    defaultDetailPlaceholder
                }
            }
        }
        .settingsKeyboardShortcuts(
            onFocusSearch: activateSearch,
            onDismissSearch: dismissSearch,
            onClose: dismissSearch
        )
        .accessibilityIdentifier("settings.threeColumnShell")
        // Auto-select first section on first appearance
        .onAppear {
            if selectedSectionID == nil {
                selectedSectionID = sections.first?.id
            }
        }
    }

    // MARK: - Col-2 page list

    @ViewBuilder
    private var pageListContent: some View {
        if let section = selectedSection {
            List(section.pages, selection: $selectedPageID) { page in
                Label(page.title, systemImage: page.icon)
                    .tag(page.id)
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier(page.id)
            }
            .navigationTitle(section.title)
            .listStyle(.insetGrouped)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    searchToolbarButton
                }
            }
        } else {
            ContentUnavailableView(
                "Select a category",
                systemImage: "sidebar.left",
                description: Text("Choose a section from the sidebar")
            )
            .accessibilityIdentifier("settings.pageList.empty")
        }
    }

    private var searchToolbarButton: some View {
        Button {
            activateSearch()
        } label: {
            Label("Search", systemImage: "magnifyingglass")
        }
        .keyboardShortcut("f", modifiers: .command)
        .accessibilityLabel("Search settings (⌘F)")
        .accessibilityIdentifier("settings.toolbar.search")
    }

    // MARK: - Col-3 placeholder

    private var defaultDetailPlaceholder: some View {
        ContentUnavailableView(
            "Select a setting",
            systemImage: "gear",
            description: Text("Choose a settings page from the list")
        )
        .accessibilityIdentifier("settings.detail.placeholder")
    }

    // MARK: - Search actions

    private func activateSearch() {
        withAnimation(.easeInOut(duration: DesignTokens.Motion.snappy)) {
            isSearchActive = true
        }
        searchFieldFocused = true
    }

    private func dismissSearch() {
        withAnimation(.easeInOut(duration: DesignTokens.Motion.snappy)) {
            isSearchActive = false
        }
        searchVM.clear()
        searchFieldFocused = false
    }

    private func handleSearchSelect(_ entry: SettingsEntry) {
        // Map the entry path back to a page ID that detailView understands.
        // Path is e.g. "settings.company.tax" — strip the prefix to get
        // the canonical settings page IDs used in SettingsView.
        let pageID = resolvePageID(from: entry)
        selectedPageID = pageID
        dismissSearch()
    }

    /// Maps a `SettingsEntry.path` to the canonical settings page ID.
    /// Falls back to the entry `id` if no explicit mapping exists.
    private func resolvePageID(from entry: SettingsEntry) -> String {
        // Many entries already have IDs that match the page IDs used by detailView
        // (e.g. "profile" → "settings.profile").  Build the canonical id by
        // prepending "settings." when needed.
        let path = entry.path
        // Direct match — already in "settings.xxx" form
        if path.hasPrefix("settings.") { return path }
        return "settings.\(entry.id)"
    }
}

// MARK: - SettingsThreeColumnShell + standard detail router

/// Convenience overload that wires the standard `SettingsView.iPadDetailView`
/// routing logic. Callers pass `api` and `isAdmin`; the shell handles the rest.
public extension SettingsThreeColumnShell where Detail == AnyView {

    /// Build the shell with the full standard page router.
    init(isAdmin: Bool = false) {
        self.init(isAdmin: isAdmin) { _ in
            AnyView(EmptyView())
        }
    }
}
