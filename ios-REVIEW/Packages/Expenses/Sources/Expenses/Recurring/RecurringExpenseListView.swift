import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - RecurringExpenseListViewModel

@MainActor
@Observable
public final class RecurringExpenseListViewModel {

    public enum LoadState: Sendable {
        case idle, loading, loaded([RecurringExpenseRule]), failed(String)
    }

    public var state: LoadState = .idle
    public var showingCreateSheet: Bool = false
    public var deletingId: Int64?
    public var errorMessage: String?

    private let runner: RecurringExpenseRunner

    public init(runner: RecurringExpenseRunner) {
        self.runner = runner
    }

    public func load() async {
        state = .loading
        do {
            let rules = try await runner.fetchRules()
            state = .loaded(rules)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func delete(rule: RecurringExpenseRule) async {
        do {
            try await runner.deleteRule(id: rule.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - RecurringExpenseListView

public struct RecurringExpenseListView: View {
    @State private var vm: RecurringExpenseListViewModel

    public init(runner: RecurringExpenseRunner) {
        _vm = State(wrappedValue: RecurringExpenseListViewModel(runner: runner))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            contentView
        }
        .navigationTitle("Recurring Expenses")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { addButton }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $vm.showingCreateSheet) {
            // Create sheet — navigates back on success
            Text("Create Recurring Expense") // placeholder; extend with form
                .onDisappear { Task { await vm.load() } }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch vm.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading recurring expenses")

        case .failed(let msg):
            VStack(spacing: BrandSpacing.md) {
                Text("Failed to load").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(msg).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }
            .padding(BrandSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded(let rules):
            if rules.isEmpty {
                emptyState
            } else {
                rulesList(rules)
            }
        }
    }

    private func rulesList(_ rules: [RecurringExpenseRule]) -> some View {
        List {
            ForEach(rules) { rule in
                RecurringRuleRow(rule: rule) {
                    Task { await vm.delete(rule: rule) }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 44))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No recurring expenses")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap + to schedule a recurring expense like rent or software subscriptions.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Add Rule") { vm.showingCreateSheet = true }
                .buttonStyle(.borderedProminent).tint(.bizarreOrange)
                .accessibilityLabel("Add a new recurring expense rule")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                vm.showingCreateSheet = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .brandGlass()
            .accessibilityLabel("Add recurring expense rule")
        }
    }
}

// MARK: - RecurringRuleRow

private struct RecurringRuleRow: View {
    let rule: RecurringExpenseRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.merchant)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(rule.category) · \(rule.frequency.displayName) · day \(rule.dayOfMonth)")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer(minLength: BrandSpacing.sm)
            Text(formatCents(rule.amountCents))
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreError)
                .monospacedDigit()
        }
        .padding(.vertical, BrandSpacing.xs)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.merchant). \(rule.category). \(rule.frequency.displayName) on day \(rule.dayOfMonth). \(formatCents(rule.amountCents)).")
    }

    private func formatCents(_ cents: Int) -> String {
        let value = Double(cents) / 100.0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}
