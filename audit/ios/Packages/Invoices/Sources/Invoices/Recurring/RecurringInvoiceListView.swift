#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §7.8 Recurring Invoice List — next-run + auto-send status

@MainActor
@Observable
final class RecurringInvoiceListViewModel {
    enum State: Sendable {
        case idle
        case loading
        case loaded([RecurringInvoiceRule])
        case failed(String)
    }

    var state: State = .idle
    var showEditor: Bool = false
    var editingRule: RecurringInvoiceRule?

    @ObservationIgnored private let api: APIClient

    init(api: APIClient) { self.api = api }

    func load() async {
        state = .loading
        do {
            let rules = try await api.listRecurringRules()
            state = .loaded(rules)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func delete(rule: RecurringInvoiceRule) async {
        do {
            try await api.deleteRecurringRule(id: rule.id)
            if case .loaded(let rules) = state {
                state = .loaded(rules.filter { $0.id != rule.id })
            }
        } catch {
            // Keep existing state; surface error inline in a production build
        }
    }
}

public struct RecurringInvoiceListView: View {
    @State private var vm: RecurringInvoiceListViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
        _vm = State(wrappedValue: RecurringInvoiceListViewModel(api: api))
    }

    public var body: some View {
        Group {
            switch vm.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let msg):
                errorView(msg)
            case .loaded(let rules):
                if rules.isEmpty {
                    emptyView
                } else {
                    listView(rules)
                }
            }
        }
        .navigationTitle("Recurring Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $vm.showEditor) {
            RecurringInvoiceEditorSheet(
                api: api,
                rule: vm.editingRule
            ) { await vm.load() }
        }
    }

    // MARK: - Subviews

    private func listView(_ rules: [RecurringInvoiceRule]) -> some View {
        List {
            ForEach(rules) { rule in
                RecurringRuleRow(rule: rule)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { await vm.delete(rule: rule) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            vm.editingRule = rule
                            vm.showEditor = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.bizarreOrange)
                    }
                    .accessibilityLabel(a11yLabel(for: rule))
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text("No recurring rules")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Tap + to set up automatic invoice generation.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .padding(BrandSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
            Text(msg)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .padding(BrandSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                vm.editingRule = nil
                vm.showEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add recurring rule")
        }
    }

    private func a11yLabel(for rule: RecurringInvoiceRule) -> String {
        let name = rule.name ?? "Rule \(rule.id)"
        let freq = rule.frequency.displayName
        let auto = rule.autoSend ? "auto-send on" : "auto-send off"
        return "\(name). \(freq). \(auto)."
    }
}

// MARK: - Row

private struct RecurringRuleRow: View {
    let rule: RecurringInvoiceRule
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(rule.name ?? "Rule \(rule.id)")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                frequencyChip
            }
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "calendar")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .imageScale(.small)
                Text("Next: \(Self.dateFormatter.string(from: rule.nextRunAt))")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .monospacedDigit()
                Spacer()
                if rule.autoSend {
                    autoSendBadge
                }
            }
        }
        .padding(.vertical, BrandSpacing.xs)
    }

    private var frequencyChip: some View {
        Text(rule.frequency.displayName)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(.bizarreOnSurface)
            .background(Color.bizarreSurface2, in: Capsule())
    }

    private var autoSendBadge: some View {
        Label("Auto-send", systemImage: "paperplane.fill")
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreSuccess)
            .labelStyle(.iconOnly)
            .accessibilityLabel("Auto-send enabled")
    }
}
#endif
