import SwiftUI
import Core
import DesignSystem
import Networking
import Sync

// MARK: - ExpensesThreeColumnView
//
// iPad-only 3-col layout:
//   Column 1 (sidebar)  — category filter list
//   Column 2 (content)  — expense list filtered by selected category
//   Column 3 (detail)   — expense detail + receipt inspector
//
// Route grounding:
//   GET  /api/v1/expenses?category=<c>   → APIClient.listExpenses(category:)
//   GET  /api/v1/expenses/:id            → APIClient.getExpense(id:)
//   DELETE /api/v1/expenses/:id          → APIClient.deleteExpense(id:)
//
// Liquid Glass chrome: toolbar bar / sidebar header use .brandGlass.
// Data rows (list cells, cards) do NOT use glass per CLAUDE.md rule.

public struct ExpensesThreeColumnView: View {

    // MARK: State

    @State private var listVM: ExpenseListViewModel
    @State private var selectedCategory: String? = nil
    @State private var selectedExpenseId: Int64? = nil
    @State private var showingCreate: Bool = false
    @State private var showingFilter: Bool = false
    @State private var searchText: String = ""

    private let api: APIClient

    // MARK: Static category list
    // Mirrors ExpenseCategory enum; presented in the sidebar for quick pivoting.
    private static let sidebarCategories: [String] = {
        var cats: [String] = ["All"]
        cats.append(contentsOf: ExpenseCategory.allCases.map(\.rawValue))
        return cats
    }()

    // MARK: Init

    public init(api: APIClient, cachedRepo: ExpenseCachedRepository? = nil) {
        self.api = api
        _listVM = State(
            wrappedValue: ExpenseListViewModel(api: api, cachedRepo: cachedRepo)
        )
    }

    // MARK: Body

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            categorySidebar
        } content: {
            expenseListColumn
        } detail: {
            expenseDetailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .task { await listVM.load() }
        .refreshable { await listVM.forceRefresh() }
        .sheet(isPresented: $showingCreate, onDismiss: {
            Task { await listVM.load() }
        }) {
            ExpenseCreateView(api: api)
        }
        .sheet(isPresented: $showingFilter, onDismiss: {
            Task { await listVM.load() }
        }) {
            ExpenseFilterSheet(filter: $listVM.filter)
                .presentationDetents([.medium])
        }
        .onChange(of: selectedCategory) { _, newCat in
            listVM.filter = ExpenseListFilter(
                category: (newCat == nil || newCat == "All") ? nil : newCat,
                fromDate: listVM.filter.fromDate,
                toDate: listVM.filter.toDate,
                status: listVM.filter.status
            )
            Task { await listVM.load() }
        }
        .onChange(of: listVM.filter) { _, _ in
            Task { await listVM.load() }
        }
    }

    // MARK: - Column 1: Category Sidebar

    private var categorySidebar: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List(Self.sidebarCategories, id: \.self, selection: $selectedCategory) { cat in
                CategorySidebarRow(
                    category: cat,
                    isSelected: selectedCategory == cat || (cat == "All" && selectedCategory == nil),
                    count: categoryCount(for: cat)
                )
                .listRowBackground(Color.bizarreSurface1)
                #if canImport(UIKit)
                .hoverEffect(.highlight)
                #endif
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New expense")
                .accessibilityIdentifier("expenses.3col.new")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            sidebarGlassHeader
        }
    }

    private var sidebarGlassHeader: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "creditcard.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Expenses")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if let s = listVM.summary {
                Text(formatMoney(s.totalAmount))
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                    .accessibilityLabel("Total \(formatMoney(s.totalAmount))")
            }
        }
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .background(.ultraThinMaterial)
    }

    // MARK: - Column 2: Expense List

    private var expenseListColumn: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            listContent
        }
        .navigationTitle(selectedCategory ?? "All Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search expenses")
        .onChange(of: searchText) { _, new in listVM.onSearchChange(new) }
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 500)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingFilter = true
                } label: {
                    Image(systemName: listVM.isFiltered
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                    .foregroundStyle(listVM.isFiltered ? Color.bizarreOrange : Color.bizarreOnSurface)
                }
                .keyboardShortcut("F", modifiers: .command)
                .accessibilityLabel(listVM.isFiltered ? "Edit filter (active)" : "Filter expenses")
                .accessibilityIdentifier("expenses.3col.filter")
            }
            ToolbarItem(placement: .automatic) {
                StalenessIndicator(lastSyncedAt: listVM.lastSyncedAt)
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if listVM.isLoading && listVM.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading expenses")
        } else if let err = listVM.errorMessage {
            errorState(err)
        } else if listVM.items.isEmpty {
            emptyState
        } else {
            expenseList
        }
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load expenses")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await listVM.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(listVM.isFiltered ? "No results for this filter" : "No expenses")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            if listVM.isFiltered {
                Button("Clear filter") { listVM.clearFilter() }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)
                    .accessibilityLabel("Clear expense filter")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var expenseList: some View {
        List(selection: $selectedExpenseId) {
            ForEach(listVM.items) { exp in
                ExpenseThreeColumnRow(expense: exp)
                    .tag(exp.id)
                    .listRowBackground(Color.bizarreSurface1)
                    #if canImport(UIKit)
                    .hoverEffect(.highlight)
                    #endif
                    .contextMenu {
                        ExpenseContextMenu(
                            expense: exp,
                            api: api,
                            onDeleted: { listVM.removeItem(id: exp.id) }
                        )
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Column 3: Detail

    @ViewBuilder
    private var expenseDetailColumn: some View {
        if let id = selectedExpenseId {
            ExpenseDetailView(api: api, id: id)
        } else {
            placeholderDetail
        }
    }

    private var placeholderDetail: some View {
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
                Text("Choose from the list to view details and receipt.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("")
    }

    // MARK: - Helpers

    private func categoryCount(for category: String) -> Int {
        guard category != "All" else { return listVM.items.count }
        return listVM.items.filter {
            $0.category?.lowercased() == category.lowercased()
        }.count
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - CategorySidebarRow

private struct CategorySidebarRow: View {
    let category: String
    let isSelected: Bool
    let count: Int

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: categoryIcon(for: category))
                .frame(width: 24)
                .foregroundStyle(isSelected ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text(category)
                .font(.brandBodyLarge())
                .foregroundStyle(isSelected ? Color.bizarreOnSurface : Color.bizarreOnSurface)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category), \(count) expense\(count == 1 ? "" : "s")")
    }

    private func categoryIcon(for cat: String) -> String {
        switch cat {
        case "All":           return "square.grid.2x2"
        case "Rent":          return "building.2"
        case "Utilities":     return "bolt"
        case "Parts":         return "wrench.and.screwdriver"
        case "Tools":         return "hammer"
        case "Marketing":     return "megaphone"
        case "Insurance":     return "shield.checkered"
        case "Payroll":       return "person.text.rectangle"
        case "Software":      return "laptopcomputer"
        case "Office Supplies": return "paperclip"
        case "Shipping":      return "shippingbox"
        case "Travel":        return "airplane"
        case "Maintenance":   return "wrench"
        case "Taxes":         return "doc.text"
        case "Fuel":          return "fuelpump"
        case "Meals":         return "fork.knife"
        default:              return "tag"
        }
    }
}

// MARK: - ExpenseThreeColumnRow

private struct ExpenseThreeColumnRow: View {
    let expense: Expense

    var body: some View {
        HStack(alignment: .top, spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(expense.category?.capitalized ?? "Uncategorized")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                if let desc = expense.description, !desc.isEmpty {
                    Text(desc)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(1)
                }
                if let date = expense.date, !date.isEmpty {
                    Text(date)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: BrandSpacing.xxs) {
                Text(formatMoney(expense.amount ?? 0))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreError)
                    .monospacedDigit()
                if let status = expense.status, !status.isEmpty {
                    Text(status.capitalized)
                        .font(.brandLabelSmall())
                        .foregroundStyle(statusColor(status))
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y)
    }

    private var a11y: String {
        var parts: [String] = [expense.category?.capitalized ?? "Uncategorized"]
        if let desc = expense.description, !desc.isEmpty { parts.append(desc) }
        if let date = expense.date, !date.isEmpty { parts.append(date) }
        parts.append(formatMoney(expense.amount ?? 0))
        if let status = expense.status, !status.isEmpty { parts.append(status) }
        return parts.joined(separator: ", ")
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func statusColor(_ status: String) -> Color {
        switch ExpenseStatus(rawValue: status) {
        case .approved: return .bizarreSuccess
        case .denied:   return .bizarreError
        default:        return .bizarreOnSurfaceMuted
        }
    }
}
