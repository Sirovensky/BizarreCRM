import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class ExpenseListViewModel {
    public private(set) var items: [Expense] = []
    public private(set) var summary: ExpensesListResponse.Summary?
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var searchQuery: String = ""

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    public init(api: APIClient) { self.api = api }

    public func load() async {
        if items.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            let resp = try await api.listExpenses(keyword: searchQuery.isEmpty ? nil : searchQuery)
            items = resp.expenses
            summary = resp.summary
        } catch {
            AppLog.ui.error("Expenses load failed: \(error.localizedDescription, privacy: .public)")
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
}

public struct ExpenseListView: View {
    @State private var vm: ExpenseListViewModel
    @State private var searchText: String = ""
    @State private var showingCreate: Bool = false
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: ExpenseListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showingCreate, onDismiss: { Task { await vm.load() } }) {
            ExpenseCreateView(api: api)
        }
    }

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search expenses")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .toolbar { newButton }
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
            .toolbar { newButton }
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
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var newButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingCreate = true } label: { Image(systemName: "plus") }
                .keyboardShortcut("N", modifiers: .command)
                .accessibilityLabel("New expense")
                .accessibilityIdentifier("expenses.new")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load expenses").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted).multilineTextAlignment(.center)
                Button("Try again") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.items.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "dollarsign.circle").font(.system(size: 48)).foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(searchText.isEmpty ? "No expenses" : "No results")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if let s = vm.summary {
                    Section {
                        HStack {
                            Text("Total").foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text(formatMoney(s.totalAmount))
                                .font(.brandTitleMedium())
                                .foregroundStyle(.bizarreOnSurface)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Count").foregroundStyle(.bizarreOnSurfaceMuted)
                            Spacer()
                            Text("\(s.totalCount)").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).monospacedDigit()
                        }
                    }
                    .listRowBackground(Color.bizarreSurface1)
                }
                Section {
                    ForEach(vm.items) { exp in
                        Row(expense: exp)
                            .listRowBackground(Color.bizarreSurface1)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

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
