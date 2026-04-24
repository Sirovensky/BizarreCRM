import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Sync

@MainActor
@Observable
public final class ExpenseListViewModel {
    public private(set) var items: [Expense] = []
    public private(set) var summary: ExpensesListResponse.Summary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    /// Active filter — drives server-side filtering via query params.
    public var filter: ExpenseListFilter = .init()
    /// Exposed for `StalenessIndicator` chip in toolbar.
    public private(set) var lastSyncedAt: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let cachedRepo: ExpenseCachedRepository?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    public init(api: APIClient, cachedRepo: ExpenseCachedRepository? = nil) {
        self.api = api
        self.cachedRepo = cachedRepo
    }

    public var isFiltered: Bool { !filter.isEmpty }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            let resp: ExpensesListResponse
            if let repo = cachedRepo {
                resp = try await repo.listExpenses(keyword: keyword, filter: filter)
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                resp = try await api.listExpenses(
                    keyword: keyword,
                    category: filter.category.flatMap { $0.isEmpty ? nil : $0 },
                    fromDate: filter.fromDate.flatMap { $0.isEmpty ? nil : $0 },
                    toDate: filter.toDate.flatMap { $0.isEmpty ? nil : $0 },
                    status: filter.status.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            items = resp.expenses
            summary = resp.summary
        } catch {
            AppLog.ui.error("Expenses load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func forceRefresh() async {
        defer { isLoading = false }
        errorMessage = nil
        do {
            let keyword: String? = searchQuery.isEmpty ? nil : searchQuery
            let resp: ExpensesListResponse
            if let repo = cachedRepo {
                resp = try await repo.forceRefresh(keyword: keyword, filter: filter)
                lastSyncedAt = await repo.lastSyncedAt
            } else {
                resp = try await api.listExpenses(
                    keyword: keyword,
                    category: filter.category.flatMap { $0.isEmpty ? nil : $0 },
                    fromDate: filter.fromDate.flatMap { $0.isEmpty ? nil : $0 },
                    toDate: filter.toDate.flatMap { $0.isEmpty ? nil : $0 },
                    status: filter.status.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            items = resp.expenses
            summary = resp.summary
        } catch {
            AppLog.ui.error("Expenses force-refresh failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func onSearchChange(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            await load()
        }
    }

    public func clearFilter() {
        filter = .init()
    }

    /// Optimistically removes an expense from the in-memory list after a
    /// successful delete from the detail or via swipe/context-menu.
    public func removeItem(id: Int64) {
        items.removeAll { $0.id == id }
    }
}

public struct ExpenseListView: View {
    @State private var vm: ExpenseListViewModel
    @State private var searchText: String = ""
    @State private var showingCreate: Bool = false
    @State private var showingFilter: Bool = false
    /// Tracks which expense is pending delete confirmation from swipe/context menu.
    @State private var pendingDeleteId: Int64?
    @State private var showDeleteConfirm: Bool = false
    private let api: APIClient

    public init(api: APIClient, cachedRepo: ExpenseCachedRepository? = nil) {
        self.api = api
        _vm = State(wrappedValue: ExpenseListViewModel(api: api, cachedRepo: cachedRepo))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.forceRefresh() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            ExpenseCreateView(api: api)
        }
        .sheet(isPresented: $showingFilter, onDismiss: { Task { await vm.load() } }) {
            ExpenseFilterSheet(filter: $vm.filter)
                .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete this expense?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteId else { return }
                Task {
                    await deleteExpense(id: id)
                    pendingDeleteId = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteId = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .onChange(of: vm.filter) { _, _ in
            Task { await vm.load() }
        }
    }

    // MARK: - Delete from list

    private func deleteExpense(id: Int64) async {
        do {
            try await api.deleteExpense(id: id)
            vm.removeItem(id: id)
        } catch {
            AppLog.ui.error("Expense delete from list failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search expenses")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .toolbar {
                filterButton
                newButton
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
            .navigationDestination(for: Int64.self) { id in
                ExpenseDetailView(api: api, id: id)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search expenses")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar {
                filterButton
                newButton
                ToolbarItem(placement: .automatic) {
                    StalenessIndicator(lastSyncedAt: vm.lastSyncedAt)
                }
            }
        } detail: {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: BrandSpacing.md) {
                    Image(systemName: "creditcard.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .accessibilityHidden(true)
                    Text("Select an expense")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
            .navigationDestination(for: Int64.self) { id in
                ExpenseDetailView(api: api, id: id)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Toolbar items

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New expense")
                .accessibilityIdentifier("expenses.new")
        }
    }

    private var filterButton: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                showingFilter = true
            } label: {
                Image(systemName: vm.isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(vm.isFiltered ? Color.bizarreOrange : Color.bizarreOnSurface)
            }
            .keyboardShortcut("F", modifiers: .command)
            .accessibilityLabel(vm.isFiltered ? "Edit filter (active)" : "Filter expenses")
            .accessibilityIdentifier("expenses.filter")
        }
    }

    // MARK: - Content states

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading expenses")
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load expenses").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty && !Reachability.shared.isOnline {
            OfflineEmptyStateView(entityName: "expenses")
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "dollarsign.circle").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(vm.isFiltered ? "No results for this filter" : (searchText.isEmpty ? "No expenses" : "No results"))
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                if vm.isFiltered {
                    Button("Clear filter") { vm.clearFilter() }
                        .buttonStyle(.bordered)
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Clear expense filter")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            expenseList
        }
    }

    private var expenseList: some View {
        List {
            if let s = vm.summary {
                Section {
                    ExpenseSummaryHeaderView(
                        summary: s,
                        categoryTotals: ExpenseSummaryHeaderView.categoryTotals(from: vm.items)
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: BrandSpacing.sm, leading: BrandSpacing.base, bottom: BrandSpacing.xs, trailing: BrandSpacing.base))
            }
            if vm.isFiltered {
                Section {
                    activeFilterChips
                }
                .listRowBackground(Color.bizarreSurface1)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            Section {
                ForEach(vm.items) { exp in
                    NavigationLink(value: exp.id) {
                        Row(expense: exp)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    // MARK: Swipe actions
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteId = exp.id
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityLabel("Delete expense")
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        NavigationLink(value: exp.id) {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Open expense detail")
                    }
                    // MARK: Context menu
                    .contextMenu {
                        NavigationLink(value: exp.id) {
                            Label("Open", systemImage: "arrow.up.forward.square")
                        }
                        .accessibilityLabel("Open expense")
                        Divider()
                        Button(role: .destructive) {
                            pendingDeleteId = exp.id
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityLabel("Delete expense")
                    }
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Active filter chips

    @ViewBuilder
    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                if let cat = vm.filter.category, !cat.isEmpty {
                    FilterChip(label: cat) { vm.filter = ExpenseListFilter(fromDate: vm.filter.fromDate, toDate: vm.filter.toDate, status: vm.filter.status) }
                }
                if let from = vm.filter.fromDate, !from.isEmpty {
                    FilterChip(label: "From \(from)") { vm.filter = ExpenseListFilter(category: vm.filter.category, toDate: vm.filter.toDate, status: vm.filter.status) }
                }
                if let to = vm.filter.toDate, !to.isEmpty {
                    FilterChip(label: "To \(to)") { vm.filter = ExpenseListFilter(category: vm.filter.category, fromDate: vm.filter.fromDate, status: vm.filter.status) }
                }
                if let status = vm.filter.status, !status.isEmpty {
                    FilterChip(label: status.capitalized) { vm.filter = ExpenseListFilter(category: vm.filter.category, fromDate: vm.filter.fromDate, toDate: vm.filter.toDate) }
                }
                Button {
                    vm.clearFilter()
                } label: {
                    Text("Clear all")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Clear all expense filters")
            }
            .padding(.vertical, BrandSpacing.xxs)
        }
    }

    // MARK: - Row

    private struct Row: View {
        let expense: Expense

        var body: some View {
            HStack(alignment: .top, spacing: BrandSpacing.md) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(expense.category?.capitalized ?? "Uncategorized")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    if let desc = expense.description, !desc.isEmpty {
                        Text(desc).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).lineLimit(2)
                    }
                    if let date = expense.date, !date.isEmpty {
                        Text(date).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
                Text(formatMoney(expense.amount ?? 0))
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
            }
            .padding(.vertical, BrandSpacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.a11y(for: expense))
        }

        static func a11y(for exp: Expense) -> String {
            var parts: [String] = [exp.category?.capitalized ?? "Uncategorized"]
            if let desc = exp.description, !desc.isEmpty { parts.append(desc) }
            if let date = exp.date, !date.isEmpty { parts.append(date) }
            parts.append(formatMoney(exp.amount ?? 0))
            return parts.joined(separator: ". ")
        }

        private static func formatMoney(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
            return f.string(from: NSNumber(value: v)) ?? "$\(v)"
        }

        private func formatMoney(_ v: Double) -> String { Self.formatMoney(v) }
    }
}

// MARK: - FilterChip helper

private struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.xxs) {
            Text(label)
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnOrange)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.bizarreOnOrange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label) filter")
        }
        .padding(.horizontal, BrandSpacing.sm)
        .padding(.vertical, BrandSpacing.xxs)
        .background(Color.bizarreOrange, in: Capsule())
    }
}
