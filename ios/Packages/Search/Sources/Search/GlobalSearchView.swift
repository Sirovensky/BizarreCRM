import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class GlobalSearchViewModel {
    public private(set) var results: GlobalSearchResults?
    public private(set) var localHits: [SearchHit] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public var query: String = ""
    public var selectedFilter: EntityFilter = .all

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let ftsStore: FTSIndexStore?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient, ftsStore: FTSIndexStore? = nil) {
        self.api = api
        self.ftsStore = ftsStore
    }

    public func onChange(_ new: String) {
        query = new
        searchTask?.cancel()
        if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = nil
            localHits = []
            errorMessage = nil
            isLoading = false
            return
        }
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await fetchLocal()
            await fetchRemote()
        }
    }

    public func submit() async {
        searchTask?.cancel()
        await fetchLocal()
        await fetchRemote()
    }

    private func fetchLocal() async {
        guard let store = ftsStore else { return }
        let filter: EntityFilter? = selectedFilter == .all ? nil : selectedFilter
        let hits = (try? await store.search(query: query, entity: filter, limit: 20)) ?? []
        localHits = hits
    }

    private func fetchRemote() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            results = try await api.globalSearch(query)
        } catch {
            AppLog.ui.error("Search failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            results = nil
        }
    }
}

public struct GlobalSearchView: View {
    @State private var vm: GlobalSearchViewModel
    @State private var queryText: String = ""
    @State private var showingFilters: Bool = false
    @State private var showingSaved: Bool = false
    @State private var filters: SearchFilters = SearchFilters()

    private let recentStore: RecentSearchStore?
    private let savedStore: SavedSearchStore?
    private let ftsStore: FTSIndexStore?

    @State private var recentQueries: [String] = []

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

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    entityFilterBar
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.xs)
                        .brandGlass(in: Rectangle())
                    content
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
            .toolbar {
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
                            Image(systemName: filters.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(filters.isDefault ? .bizarreOnSurface : .bizarreOrange)
                        }
                        .accessibilityLabel(filters.isDefault ? "Filters" : "Filters active")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                SearchFiltersSheet(filters: $filters) { applied in
                    vm.selectedFilter = applied.entity
                    Task { await vm.submit() }
                }
            }
            .sheet(isPresented: $showingSaved) {
                if let savedStore, let ftsStore {
                    SavedSearchListView(store: savedStore, ftsStore: ftsStore)
                }
            }
            .task { await loadRecent() }
        }
    }

    // MARK: - Entity filter chips

    private var entityFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(EntityFilter.allCases, id: \.self) { filter in
                    Button {
                        vm.selectedFilter = filter
                        if !queryText.isEmpty { Task { await vm.submit() } }
                    } label: {
                        Label(filter.displayName, systemImage: filter.systemImage)
                            .font(.brandLabelLarge())
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .brandGlass(vm.selectedFilter == filter ? .identity : .regular, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter.displayName)
                    .accessibilityAddTraits(vm.selectedFilter == filter ? .isSelected : [])
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if queryText.isEmpty && !Reachability.shared.isOnline {
            offlinePlaceholder
        } else if queryText.isEmpty {
            emptyStateWithRecent
        } else if vm.isLoading && vm.localHits.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.localHits.isEmpty {
            errorView(err)
        } else if let results = vm.results {
            if results.isEmpty && vm.localHits.isEmpty {
                noResultsView
            } else {
                resultList(results: results)
            }
        } else if !vm.localHits.isEmpty {
            localHitList
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
                        onSelect: { query in
                            queryText = query
                            vm.onChange(query)
                        },
                        onDelete: { query in
                            Task {
                                await recentStore?.remove(query)
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
                    Text("Search across tickets, customers, inventory, and invoices.")
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
            Text("No results for \"\(queryText)\"")
                .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
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

    // MARK: - Local hits (FTS fast lane)

    private var localHitList: some View {
        List {
            Section("Local results") {
                ForEach(vm.localHits) { hit in
                    SearchHitRow(hit: hit)
                        .listRowBackground(Color.bizarreSurface1)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Remote results

    private func resultList(results: GlobalSearchResults) -> some View {
        List {
            // Show local hits first (fast lane)
            if !vm.localHits.isEmpty {
                Section("Local") {
                    ForEach(vm.localHits) { hit in
                        SearchHitRow(hit: hit)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            if !results.customers.isEmpty {
                Section("Customers") {
                    ForEach(results.customers) { row in
                        ResultRow(row: row, icon: "person.fill")
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            if !results.tickets.isEmpty {
                Section("Tickets") {
                    ForEach(results.tickets) { row in
                        ResultRow(row: row, icon: "wrench.and.screwdriver.fill")
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            if !results.inventory.isEmpty {
                Section("Inventory") {
                    ForEach(results.inventory) { row in
                        ResultRow(row: row, icon: "shippingbox.fill")
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            if !results.invoices.isEmpty {
                Section("Invoices") {
                    ForEach(results.invoices) { row in
                        ResultRow(row: row, icon: "doc.text.fill")
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
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

    // MARK: - Result row

    private struct ResultRow: View {
        let row: GlobalSearchResults.Row
        let icon: String
        @State private var copied: Bool = false

        var body: some View {
            HStack(spacing: BrandSpacing.md) {
                Image(systemName: icon)
                    .foregroundStyle(.bizarreOrange)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.display ?? "—")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    if let sub = row.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.bizarreSuccess)
                        .transition(.opacity)
                        .accessibilityLabel("Copied")
                }
            }
            .padding(.vertical, BrandSpacing.xxs)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    copy(String(row.id))
                } label: {
                    Label("Copy ID #\(row.id)", systemImage: "number.square")
                }
                if let display = row.display, !display.isEmpty {
                    Button {
                        copy(display)
                    } label: {
                        Label("Copy name", systemImage: "doc.on.doc")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: row))
            .accessibilityHint("Double-tap and hold to open the actions menu.")
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

        static func a11y(for row: GlobalSearchResults.Row) -> String {
            let display = row.display ?? "Untitled"
            let sub = row.subtitle ?? ""
            return sub.isEmpty ? display : "\(display). \(sub)"
        }
    }
}
