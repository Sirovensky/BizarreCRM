import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ViewModel

@MainActor
@Observable
public final class GlobalSearchViewModel {

    // MARK: - Observable state

    public private(set) var mergedRows: [SearchResultMerger.MergedRow] = []
    /// Kept for backward compatibility — callers that need the raw server response.
    public private(set) var results: GlobalSearchResults?
    public private(set) var localHits: [SearchHit] = []
    public private(set) var scopeCounts: ScopeCounts = .zero
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var query: String = ""
    public var selectedFilter: EntityFilter = .all

    // MARK: - §18.1 Type-ahead preview state

    /// Top-3 hits shown in dropdown before full search runs.
    public private(set) var typeAheadHits: [TypeAheadHit] = []
    /// True while the dropdown should be visible (non-empty query, before "See all" tap).
    public var showTypeAhead: Bool = false

    // MARK: - Private

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ftsStore: FTSIndexStore?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var typeAheadTask: Task<Void, Never>?

    // MARK: - Init

    public init(api: APIClient, ftsStore: FTSIndexStore? = nil) {
        self.api = api
        self.ftsStore = ftsStore
    }

    // MARK: - Public API

    public func onChange(_ new: String) {
        query = new
        searchTask?.cancel()
        typeAheadTask?.cancel()
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = nil
            localHits = []
            mergedRows = []
            scopeCounts = .zero
            errorMessage = nil
            isLoading = false
            typeAheadHits = []
            showTypeAhead = false
            return
        }
        searchTask = Task { @MainActor in
            // §18.1 250ms debounce — cancel prior request on each keystroke.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            await fetchTypeAhead(new)
        }
        searchTask = Task { @MainActor in
            // §18.1 250ms debounce — cancel prior request on each keystroke.
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            // Full search hides type-ahead once results are ready.
            showTypeAhead = false
            await fetchLocal()
            await fetchRemote()
        }
    }

    /// Feeds top-3 hits from local FTS into `typeAheadHits`.
    private func fetchTypeAhead(_ q: String) async {
        guard let store = ftsStore else { return }
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let hits = try await store.search(query: trimmed, entity: nil, limit: 3)
            typeAheadHits = hits.map { hit in
                TypeAheadHit(
                    id: hit.id,
                    type: hit.entity,
                    title: hit.title,
                    subtitle: hit.snippet.isEmpty ? nil : hit.snippet,
                    badge: nil,
                    entityId: Int64(hit.entityId)
                )
            }
            showTypeAhead = !typeAheadHits.isEmpty
        } catch {
            // Silent — full search will cover this.
        }
    }

    public func submit() async {
        searchTask?.cancel()
        await fetchLocal()
        await fetchRemote()
    }

    // MARK: - Private fetch

    private func fetchLocal() async {
        guard let store = ftsStore else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let filter: EntityFilter? = selectedFilter == .all ? nil : selectedFilter
            async let hitsResult = store.search(query: trimmed, entity: filter, limit: 50)
            async let countsResult = store.scopeCounts(query: trimmed)
            let (hits, counts) = try await (hitsResult, countsResult)
            localHits = hits
            scopeCounts = counts
        } catch {
            // FTS5 schema not yet migrated (first run) or store error — degrade gracefully.
            AppLog.ui.error("FTS local search error: \(error.localizedDescription, privacy: .public)")
            localHits = []
        }
        updateMergedRows()
    }

    private func fetchRemote() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let remote = try await api.globalSearch(trimmed)
            results = remote
            // Merge scope counts with remote results.
            scopeCounts = scopeCounts.merged(with: remote)
            updateMergedRows()
        } catch {
            AppLog.ui.error("Search remote failed: \(error.localizedDescription, privacy: .public)")
            if results == nil {
                errorMessage = error.localizedDescription
            }
            updateMergedRows()
        }
    }

    private func updateMergedRows() {
        mergedRows = SearchResultMerger.merge(
            localHits: localHits,
            remote: results,
            filter: selectedFilter
        )
    }
}

// MARK: - GlobalSearchView

public struct GlobalSearchView: View {

    @State private var vm: GlobalSearchViewModel
    @State private var queryText: String = ""
    @State private var showingFilters: Bool = false
    @State private var showingSaved: Bool = false
    @State private var filters: SearchFilters = SearchFilters()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// §18.1 — ⌘F focuses the search field. Flipping this bool is the simplest
    /// way to re-focus `.searchable` without UIKit introspection.
    @State private var searchFocused: Bool = false
    /// §18.1 — callback invoked when user taps a type-ahead hit to deep-link navigate.
    public var onSelectTypeAheadHit: ((TypeAheadHit) -> Void)?

    private let recentStore: RecentSearchStore?
    private let savedStore: SavedSearchStore?
    private let ftsStore: FTSIndexStore?

    @State private var recentQueries: [String] = []

    // MARK: - Init

    public init(
        api: APIClient,
        ftsStore: FTSIndexStore? = nil,
        recentStore: RecentSearchStore? = nil,
        savedStore: SavedSearchStore? = nil
    ) {
        _vm = State(wrappedValue: GlobalSearchViewModel(api: api, ftsStore: ftsStore))
        self.ftsStore = ftsStore
        self.recentStore = recentStore
        self.savedStore = savedStore
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            if horizontalSizeClass == .regular {
                ipadLayout
            } else {
                iphoneLayout
            }
            // §18.1 — Invisible button captures ⌘F globally and flips searchFocused.
            // The layouts use `.searchable(text:isPresented:)` which responds to
            // the focused state flip on iPad/Mac. On iPhone the toolbar search
            // icon uses the same toggle.
            Button("") { searchFocused = true }
                .opacity(0)
                .accessibilityHidden(true)
                .keyboardShortcut("f", modifiers: .command)
        }
    }

    // MARK: - iPhone layout

    private var iphoneLayout: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    entityFilterBar
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.xs)
                        .brandGlass(in: Rectangle())
                    content
                }
                // §18.1 Type-ahead preview dropdown — floats above content below the filter bar.
                if vm.showTypeAhead && !vm.typeAheadHits.isEmpty {
                    typeAheadOverlay
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, 52) // approximately below filter bar height
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .zIndex(10)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $queryText, prompt: "Find tickets, customers, items…")
            .onChange(of: queryText) { _, new in vm.onChange(new) }
            .onSubmit(of: .search) {
                Task {
                    vm.showTypeAhead = false
                    await vm.submit()
                    if !queryText.isEmpty { await recentStore?.add(queryText) }
                }
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .sheet(isPresented: $showingSaved) { savedSheet }
            .task { await loadRecent() }
        }
    }

    /// §18.1 — Floating type-ahead card with top-3 hits + "See all" footer.
    @ViewBuilder
    private var typeAheadOverlay: some View {
        TypeAheadPreviewView(
            query: queryText,
            hits: vm.typeAheadHits,
            onSelectHit: { hit in
                withAnimation(BrandMotion.snappy) { vm.showTypeAhead = false }
                onSelectTypeAheadHit?(hit)
            },
            onSeeAll: {
                withAnimation(BrandMotion.snappy) { vm.showTypeAhead = false }
                Task {
                    await vm.submit()
                    if !queryText.isEmpty { await recentStore?.add(queryText) }
                }
            }
        )
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    // MARK: - iPad layout
    //
    // NOTE: GlobalSearchView is mounted in the *detail* column of the app-level
    // NavigationSplitView (see RootView.iPadSplit).  iOS 17 crashes if a second
    // NavigationSplitView is nested inside a NavigationSplitView detail column,
    // so ipadLayout uses a plain HStack split instead of NavigationSplitView.

    private var ipadLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                HStack(spacing: 0) {
                    // Left panel: filter chips + recent searches
                    ZStack(alignment: .top) {
                        Color.bizarreSurfaceBase.ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 0) {
                            entityFilterChipList
                                .padding(BrandSpacing.base)
                            if !recentQueries.isEmpty && queryText.isEmpty {
                                Divider().padding(.horizontal, BrandSpacing.base)
                                RecentSearchesView(
                                    queries: recentQueries,
                                    onSelect: { q in
                                        queryText = q
                                        vm.onChange(q)
                                    },
                                    onDelete: { q in
                                        Task {
                                            await recentStore?.remove(q)
                                            await loadRecent()
                                        }
                                    }
                                )
                                .padding(.top, BrandSpacing.sm)
                            }
                            Spacer()
                        }
                    }
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

                    Divider()

                    // Right panel: results
                    ZStack {
                        Color.bizarreSurfaceBase.ignoresSafeArea()
                        content
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $queryText, prompt: "Find tickets, customers, items…")
            .onChange(of: queryText) { _, new in vm.onChange(new) }
            .onSubmit(of: .search) {
                Task {
                    await vm.submit()
                    if !queryText.isEmpty { await recentStore?.add(queryText) }
                }
            }
            .toolbar { toolbarItems }
            .sheet(isPresented: $showingFilters) { filtersSheet }
            .sheet(isPresented: $showingSaved) { savedSheet }
        }
        .task { await loadRecent() }
    }

    // MARK: - Entity filter chip bar (horizontal scroll — iPhone)

    private var entityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(EntityFilter.allCases, id: \.self) { filter in
                    filterChipButton(filter)
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Entity filter chip list (vertical — iPad sidebar)

    private var entityFilterChipList: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Scope")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.bottom, BrandSpacing.xxs)
            ForEach(EntityFilter.allCases, id: \.self) { filter in
                filterChipButton(filter)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func filterChipButton(_ filter: EntityFilter) -> some View {
        Button {
            withAnimation(reduceMotion ? .none : BrandMotion.snappy) {
                vm.selectedFilter = filter
            }
            if !queryText.isEmpty { Task { await vm.submit() } }
        } label: {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: filter.systemImage)
                    .frame(width: 20)
                Text(filter.displayName)
                Spacer(minLength: 0)
                let count = vm.scopeCounts.count(for: filter)
                if count > 0 {
                    Text("\(min(count, 99))")
                        .font(.brandLabelSmall().monospacedDigit())
                        .foregroundStyle(vm.selectedFilter == filter ? .white : .bizarreOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(vm.selectedFilter == filter
                                      ? Color.bizarreOrange
                                      : Color.bizarreOrange.opacity(0.15))
                        )
                }
            }
            .font(.brandLabelLarge())
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xs)
            .brandGlass(vm.selectedFilter == filter ? .identity : .regular, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filter.displayName)
        .accessibilityValue(
            vm.scopeCounts.count(for: filter) > 0
                ? "\(vm.scopeCounts.count(for: filter)) results"
                : "no results"
        )
        .accessibilityAddTraits(vm.selectedFilter == filter ? .isSelected : [])
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            HStack(spacing: BrandSpacing.md) {
                if savedStore != nil {
                    Button {
                        showingSaved = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    .accessibilityLabel("Saved searches")
                }
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: filters.isDefault
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filters.isDefault ? .bizarreOnSurface : .bizarreOrange)
                }
                .accessibilityLabel(filters.isDefault ? "Filters" : "Filters active")
            }
        }
    }

    // MARK: - Sheets

    private var filtersSheet: some View {
        SearchFiltersSheet(filters: $filters) { applied in
            vm.selectedFilter = applied.entity
            Task { await vm.submit() }
        }
    }

    @ViewBuilder
    private var savedSheet: some View {
        if let savedStore, let ftsStore {
            SavedSearchListView(store: savedStore, ftsStore: ftsStore)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if queryText.isEmpty && !Reachability.shared.isOnline {
            offlinePlaceholder
        } else if queryText.isEmpty {
            emptyStateWithRecent
        } else if vm.isLoading && vm.mergedRows.isEmpty {
            skeletonView
        } else if let err = vm.errorMessage, vm.mergedRows.isEmpty {
            errorView(err)
        } else if !vm.mergedRows.isEmpty {
            mergedResultList
        } else if !vm.isLoading {
            noResultsView
        }
    }

    // MARK: - Placeholder states

    private var offlinePlaceholder: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreWarning)
                .accessibilityHidden(true)
            Text("Search requires network")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Connect to the internet to search tickets, customers, inventory, and invoices.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Search requires a network connection.")
    }

    private var emptyStateWithRecent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                if !recentQueries.isEmpty {
                    RecentSearchesView(
                        queries: recentQueries,
                        onSelect: { q in
                            queryText = q
                            vm.onChange(q)
                        },
                        onDelete: { q in
                            Task {
                                await recentStore?.remove(q)
                                await loadRecent()
                            }
                        }
                    )
                }
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Try a phone number, ticket ID, SKU, IMEI, or name.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BrandSpacing.lg)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, BrandSpacing.lg)
        }
    }

    private var noResultsView: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No matches for \"\(queryText)\"")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text("Try different spelling, scope to All, or search by phone.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No results for \(queryText)")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Search failed").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            Text(message).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center).padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Skeleton loader

    private var skeletonView: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonRow()
                    .listRowBackground(Color.bizarreSurface1)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
        .disabled(true)
    }

    // MARK: - Merged result list

    private var mergedResultList: some View {
        // §18.7 — When offline and server hasn't responded, all rows are from local cache.
        let isOffline = !Reachability.shared.isOnline && vm.results == nil
        return List {
            ForEach(vm.mergedRows) { row in
                // Local-only rows shown while offline carry a "cached" stale badge.
                let isLocalOffline: Bool = {
                    if case .local = row { return isOffline }
                    return false
                }()
                MergedResultRow(row: row, query: queryText, isOfflineResult: isLocalOffline)
                    .listRowBackground(Color.bizarreSurface1)
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Helpers

    private func loadRecent() async {
        recentQueries = await recentStore?.all ?? []
    }
}

// MARK: - MergedResultRow

private struct MergedResultRow: View {
    let row: SearchResultMerger.MergedRow
    let query: String
    /// §18.7 — When true, row came from local cache while offline; show stale badge.
    var isOfflineResult: Bool = false
    @State private var copied: Bool = false

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            entityIcon
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(TermHighlighter.highlight(text: row.title, query: query))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                subtitleContent
                HStack(spacing: BrandSpacing.xs) {
                    entityBadge
                    // §18.7 Offline stale badge — indicates result is from local cache.
                    if isOfflineResult {
                        Text("cached")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreWarning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
                            .accessibilityLabel("Offline cached result")
                    }
                }
            }
            Spacer()
            copiedIndicator
        }
        .padding(.vertical, BrandSpacing.xxs)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                copy(row.entityId)
            } label: {
                Label("Copy ID \(row.entityId)", systemImage: "number.square")
            }
            if !row.title.isEmpty {
                Button {
                    copy(row.title)
                } label: {
                    Label("Copy name", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint("Double-tap and hold to open the actions menu.")
    }

    @ViewBuilder
    private var subtitleContent: some View {
        if let snippet = row.snippet, !snippet.isEmpty {
            // FTS5 snippet with <b>…</b> markers → AttributedString
            Text(TermHighlighter.attributed(snippet: snippet))
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(2)
        } else if let sub = row.subtitle, !sub.isEmpty {
            Text(TermHighlighter.highlight(text: sub, query: query))
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .lineLimit(1)
        }
    }

    private var entityBadge: some View {
        Text(row.entity.capitalized)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOrange)
    }

    private var entityIcon: some View {
        let imageName: String
        switch row.entity {
        case "customers":    imageName = "person.fill"
        case "tickets":      imageName = "wrench.and.screwdriver.fill"
        case "inventory":    imageName = "shippingbox.fill"
        case "invoices":     imageName = "doc.text.fill"
        case "estimates":    imageName = "doc.badge.plus"
        case "appointments": imageName = "calendar"
        default:             imageName = "magnifyingglass"
        }
        return Image(systemName: imageName)
            .foregroundStyle(.bizarreOrange)
    }

    @ViewBuilder
    private var copiedIndicator: some View {
        if copied {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.bizarreSuccess)
                .transition(.opacity)
                .accessibilityLabel("Copied")
        }
    }

    private var a11yLabel: String {
        let sub = row.subtitle ?? row.snippet ?? ""
        return sub.isEmpty ? row.title : "\(row.title). \(sub)"
    }

    private func copy(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
        withAnimation(BrandMotion.snappy) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(BrandMotion.snappy) { copied = false }
        }
    }
}

// MARK: - SkeletonRow

private struct SkeletonRow: View {
    var body: some View {
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
        .accessibilityHidden(true)
    }
}
