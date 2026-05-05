import SwiftUI
import DesignSystem
import Networking

/// §22.1 — iPad-optimised 3-column search layout.
///
///   Column 1 (sidebar):  `SearchScopeSidebar` — scope toggles with result counts.
///   Column 2 (content):  Merged result list with `.searchable` and Liquid Glass toolbar.
///   Column 3 (preview):  `SearchResultPreviewPane` — inline preview of selected result.
///
/// The view owns its own `GlobalSearchViewModel` so it can be dropped into any
/// `NavigationSplitView` detail column or used as a standalone fullscreen view.
///
/// Example:
/// ```swift
/// SearchThreeColumnView(api: apiClient, ftsStore: ftsStore)
/// ```
@MainActor
public struct SearchThreeColumnView: View {

    // MARK: - State

    @State private var vm: GlobalSearchViewModel
    @State private var queryText: String = ""
    @State private var selectedScope: SearchScope = .all
    @State private var selectedIndex: Int? = nil
    @State private var selectedPreviewItem: SearchPreviewItem? = nil
    @FocusState private var focusedField: SearchFocusField?

    // MARK: - Private stored

    private let ftsStore: FTSIndexStore?
    private let onOpen: ((SearchPreviewItem) -> Void)?

    // MARK: - Init

    /// - Parameters:
    ///   - api: The API client used for remote global search.
    ///   - ftsStore: Optional local FTS5 index (enables offline + instant results).
    ///   - onOpen: Called when the user activates a result (taps "Open" or presses Return).
    ///             The host app should push the appropriate entity detail view.
    public init(
        api: APIClient,
        ftsStore: FTSIndexStore? = nil,
        onOpen: ((SearchPreviewItem) -> Void)? = nil
    ) {
        _vm = State(wrappedValue: GlobalSearchViewModel(api: api, ftsStore: ftsStore))
        self.ftsStore = ftsStore
        self.onOpen = onOpen
    }

    // MARK: - Derived state

    private var scopeCounts: SearchScopeCounts {
        SearchScopeCounts.from(hits: vm.localHits)
            .merged(with: vm.scopeCounts)
    }

    private var filteredRows: [SearchResultMerger.MergedRow] {
        guard selectedScope != .all else { return vm.mergedRows }
        return vm.mergedRows.filter { $0.entity == selectedScope.rawValue }
    }

    // MARK: - Body

    public var body: some View {
        NavigationSplitView {
            // Column 1 — Scope Sidebar
            SearchScopeSidebar(
                selectedScope: $selectedScope,
                counts: scopeCounts,
                onScopeSelected: { _ in
                    // Refilter clears selection when scope changes
                    selectedIndex = nil
                    selectedPreviewItem = nil
                }
            )
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
        } content: {
            // Column 2 — Result List
            resultListColumn
                .navigationTitle(selectedScope.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $queryText, placement: .navigationBarDrawer, prompt: searchPrompt)
                .focused($focusedField, equals: .searchBar)
                .onChange(of: queryText) { _, new in
                    vm.onChange(new)
                    selectedIndex = nil
                    selectedPreviewItem = nil
                }
                .onSubmit(of: .search) {
                    Task { await vm.submit() }
                }
                .toolbar { resultListToolbar }
        } detail: {
            // Column 3 — Preview Pane
            SearchResultPreviewPane(
                selectedItem: selectedPreviewItem,
                onOpen: { item in onOpen?(item) }
            )
            .navigationTitle(selectedPreviewItem?.title ?? "Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
        .searchKeyboardShortcuts(
            selectedScope: $selectedScope,
            focusedField: Binding(
                get: { focusedField },
                set: { focusedField = $0 }
            ),
            hitCount: filteredRows.count,
            selectedIndex: $selectedIndex,
            onOpen: {
                guard let item = selectedPreviewItem else { return }
                onOpen?(item)
            }
        )
        .onChange(of: selectedIndex) { _, idx in
            updatePreview(for: idx)
        }
    }

    // MARK: - Result list column

    @ViewBuilder
    private var resultListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()

            if queryText.isEmpty {
                emptyQueryState
            } else if vm.isLoading && filteredRows.isEmpty {
                skeletonList
            } else if let err = vm.errorMessage, filteredRows.isEmpty {
                errorState(err)
            } else if filteredRows.isEmpty && !vm.isLoading {
                noResultsState
            } else {
                resultList
            }
        }
    }

    // MARK: - Result list

    private var resultList: some View {
        List(selection: $selectedIndex) {
            ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                resultRow(row, index: index)
                    .tag(index)
                    .listRowBackground(Color.bizarreSurface1)
                    .brandHover()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedIndex) { _, idx in
            updatePreview(for: idx)
        }
    }

    private func resultRow(_ row: SearchResultMerger.MergedRow, index: Int) -> some View {
        let isSelected = selectedIndex == index
        return HStack(spacing: BrandSpacing.md) {
            entityIcon(row.entity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(TermHighlighter.highlight(text: row.title, query: queryText))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)

                if let snippet = row.snippet, !snippet.isEmpty {
                    Text(TermHighlighter.attributed(snippet: snippet))
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                } else if let sub = row.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }

                Text(row.entity.capitalized)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
            }

            Spacer()

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(BrandMotion.snappy) {
                selectedIndex = index
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowA11yLabel(row))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Entity icon

    private func entityIcon(_ entity: String) -> some View {
        let imageName: String
        switch entity {
        case "customers":    imageName = "person.fill"
        case "tickets":      imageName = "wrench.and.screwdriver.fill"
        case "inventory":    imageName = "shippingbox.fill"
        case "invoices":     imageName = "doc.text.fill"
        case "estimates":    imageName = "doc.badge.plus"
        case "appointments": imageName = "calendar"
        case "notes":        imageName = "note.text"
        default:             imageName = "doc.fill"
        }
        return Image(systemName: imageName)
            .foregroundStyle(.bizarreOrange)
            .frame(width: 28)
    }

    // MARK: - Placeholder states

    private var emptyQueryState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Type to search")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Search across \(selectedScope == .all ? "all entities" : selectedScope.displayName.lowercased()).")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No search query. Type to search.")
    }

    private var noResultsState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No matches for \"\(queryText)\"")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Try a different query or switch scope to All.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(queryText)")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Search failed")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(message)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, BrandSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search failed. \(message)")
    }

    private var skeletonList: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: BrandSpacing.md) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.bizarreOnSurface.opacity(0.08))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOnSurface.opacity(0.08))
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.bizarreOnSurface.opacity(0.05))
                            .frame(maxWidth: 180)
                            .frame(height: 12)
                    }
                }
                .padding(.vertical, BrandSpacing.xxs)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityHidden(true)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .disabled(true)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var resultListToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            BrandGlassBadge(
                "\(filteredRows.count)",
                variant: .regular,
                tint: filteredRows.isEmpty ? nil : .bizarreOrange
            )
            .opacity(filteredRows.isEmpty ? 0 : 1)
            .animation(BrandMotion.snappy, value: filteredRows.count)
            .accessibilityLabel("\(filteredRows.count) results")
        }
    }

    // MARK: - Helpers

    private var searchPrompt: String {
        "Search \(selectedScope == .all ? "everything" : selectedScope.displayName.lowercased())…"
    }

    private func updatePreview(for index: Int?) {
        guard let index, index < filteredRows.count else {
            selectedPreviewItem = nil
            return
        }
        selectedPreviewItem = SearchPreviewItem.from(row: filteredRows[index])
    }

    private func rowA11yLabel(_ row: SearchResultMerger.MergedRow) -> String {
        let sub = row.snippet ?? row.subtitle ?? ""
        return sub.isEmpty ? "\(row.title), \(row.entity)" : "\(row.title), \(sub), \(row.entity)"
    }
}
