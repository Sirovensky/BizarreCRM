import SwiftUI
import Observation
import UniformTypeIdentifiers
import Core
import DesignSystem
import Networking
import Sync

// MARK: - §11.1 Sort option

/// Client-side sort applied after data loads from cache/server.
public enum ExpenseSortOption: String, CaseIterable, Identifiable, Sendable {
    case dateDesc     = "date_desc"
    case dateAsc      = "date_asc"
    case amountDesc   = "amount_desc"
    case amountAsc    = "amount_asc"
    case categoryAsc  = "category_asc"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dateDesc:    return "Newest first"
        case .dateAsc:     return "Oldest first"
        case .amountDesc:  return "Amount (high)"
        case .amountAsc:   return "Amount (low)"
        case .categoryAsc: return "Category A→Z"
        }
    }
}

@MainActor
@Observable
public final class ExpenseListViewModel {
    public private(set) var items: [Expense] = []
    public private(set) var summary: ExpensesListResponse.Summary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""
    // §11.1 sort
    public var sortOption: ExpenseSortOption = .dateDesc
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

    // MARK: - §11.1 Sorted items

    /// Returns `items` sorted per `sortOption`. Pure derivation — no network call.
    public var sortedItems: [Expense] {
        switch sortOption {
        case .dateDesc:
            return items.sorted { ($0.date ?? "") > ($1.date ?? "") }
        case .dateAsc:
            return items.sorted { ($0.date ?? "") < ($1.date ?? "") }
        case .amountDesc:
            return items.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
        case .amountAsc:
            return items.sorted { ($0.amount ?? 0) < ($1.amount ?? 0) }
        case .categoryAsc:
            return items.sorted { ($0.category ?? "") < ($1.category ?? "") }
        }
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
    // §11.1 CSV export
    @State private var csvExportItem: ExportableExpenseCSV?
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
        // §11.1 CSV export via fileExporter
        .fileExporter(
            isPresented: Binding(get: { csvExportItem != nil }, set: { if !$0 { csvExportItem = nil } }),
            document: csvExportItem,
            contentType: .commaSeparatedText,
            defaultFilename: "expenses.csv"
        ) { result in
            switch result {
            case .success: AppLog.ui.info("Expenses CSV exported successfully")
            case .failure(let error): AppLog.ui.error("Expenses CSV export failed: \(error.localizedDescription, privacy: .public)")
            }
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
                sortButton
                exportButton
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
                sortButton
                exportButton
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

    /// §11.1 Sort menu — client-side sort applied to loaded items.
    private var sortButton: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(ExpenseSortOption.allCases) { opt in
                    Button {
                        vm.sortOption = opt
                    } label: {
                        if vm.sortOption == opt {
                            Label(opt.displayName, systemImage: "checkmark")
                        } else {
                            Text(opt.displayName)
                        }
                    }
                    .accessibilityLabel("Sort by \(opt.displayName)")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
            .accessibilityLabel("Sort expenses")
            .accessibilityIdentifier("expenses.sort")
        }
    }

    /// §11.1 Export CSV — exports current sorted list.
    private var exportButton: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Button {
                let data = ExpenseBulkCSVExporter.csv(from: vm.sortedItems)
                csvExportItem = ExportableExpenseCSV(data: data)
            } label: {
                Label("Export CSV", systemImage: "arrow.down.doc")
            }
            .accessibilityLabel("Export all expenses as CSV")
            .accessibilityIdentifier("expenses.export")
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
            // §11 Expense list empty state — distinct messaging for each scenario
            expenseEmptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            expenseList
        }
    }

    /// §11 Expense list empty state — three distinct scenarios each get a
    /// dedicated icon + headline + body + optional CTA.
    @ViewBuilder
    private var expenseEmptyState: some View {
        if !searchText.isEmpty {
            // Search returned nothing
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No results for "\(searchText)"")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .multilineTextAlignment(.center)
                Text("Try a different vendor, category, or date range.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No results for \(searchText). Try a different search term.")
        } else if vm.isFiltered {
            // Filter active, nothing matches
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No expenses match this filter")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Adjust or clear the filter to see all expenses.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button("Clear filter") { vm.clearFilter() }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Clear expense filter")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No expenses match the current filter. Double-tap to clear.")
        } else {
            // No expenses at all — encourage the user to add one
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.55))
                    .accessibilityHidden(true)
                Text("No expenses yet")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text("Track your first business expense to keep your books up to date.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
                Button {
                    showingCreate = true
                } label: {
                    Label("Add expense", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Add first expense")
                .accessibilityIdentifier("expenses.emptyState.add")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("No expenses yet. Double-tap the Add expense button to get started.")
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
                ForEach(vm.sortedItems) { exp in
                    NavigationLink(value: exp.id) {
                        Row(expense: exp)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    // MARK: §11.1 Swipe actions — leading: Edit; trailing: Delete
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
                            Label("Open", systemImage: "pencil")
                        }
                        .tint(.bizarreOrange)
                        .accessibilityLabel("Open expense to edit")
                    }
                    // MARK: §11.1 Context menu — Open / Duplicate / Export / Delete
                    .contextMenu {
                        ExpenseContextMenu(
                            expense: exp,
                            api: api,
                            onDuplicated: { _ in Task { await vm.load() } },
                            onDeleted: {
                                vm.removeItem(id: exp.id)
                            }
                        )
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

        /// §11 Amount format — uses device locale so non-USD tenants see their
        /// local currency symbol instead of a hard-coded "$".
        private static func formatMoney(_ v: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .currency
            f.locale = .current
            return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
        }

        private func formatMoney(_ v: Double) -> String { Self.formatMoney(v) }
    }
}

// MARK: - §11.1 Bulk CSV export

/// RFC-4180 CSV builder for an array of expenses.
public enum ExpenseBulkCSVExporter {
    private static let header = "id,category,amount,date,description,vendor,status,payment_method,notes,reimbursable"

    public static func csv(from expenses: [Expense]) -> Data {
        var lines: [String] = [header]
        for exp in expenses {
            let row = [
                "\(exp.id)",
                escape(exp.category),
                exp.amount.map { String(format: "%.2f", $0) } ?? "",
                escape(exp.date),
                escape(exp.description),
                escape(exp.vendor),
                escape(exp.status),
                escape(exp.paymentMethod),
                escape(exp.notes),
                exp.isReimbursable == true ? "true" : "false"
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\r\n").data(using: .utf8) ?? Data()
    }

    private static func escape(_ value: String?) -> String {
        guard let v = value, !v.isEmpty else { return "" }
        let escaped = v.replacingOccurrences(of: "\"", with: "\"\"")
        let needsQuotes = escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}

/// `FileDocument` wrapper for `.fileExporter`.
public struct ExportableExpenseCSV: FileDocument {
    public static let readableContentTypes = [UTType.commaSeparatedText]
    public let data: Data

    public init(data: Data) { self.data = data }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
