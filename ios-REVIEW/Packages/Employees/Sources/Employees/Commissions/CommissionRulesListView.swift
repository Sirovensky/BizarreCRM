import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - CommissionRulesListViewModel

@MainActor
@Observable
public final class CommissionRulesListViewModel {
    public private(set) var rules: [CommissionRule] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func load() async {
        if rules.isEmpty { isLoading = true }
        defer { isLoading = false }
        errorMessage = nil
        do {
            rules = try await api.listCommissionRules()
        } catch {
            AppLog.ui.error("Commission rules load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func delete(rule: CommissionRule) async {
        let id = rule.id
        rules.removeAll { $0.id == id }
        do {
            try await api.deleteCommissionRule(id: id)
        } catch {
            AppLog.ui.error("Commission rule delete failed: \(error.localizedDescription, privacy: .public)")
            await load()
        }
    }
}

// MARK: - CommissionRulesListView

public struct CommissionRulesListView: View {
    @State private var vm: CommissionRulesListViewModel
    @State private var editingRule: CommissionRule?
    @State private var showEditor: Bool = false

    public init(api: APIClient) {
        _vm = State(wrappedValue: CommissionRulesListViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact { compactLayout } else { regularLayout }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .sheet(isPresented: $showEditor, onDismiss: { editingRule = nil }) {
            CommissionRuleEditorSheet(rule: editingRule, api: vm.apiRef) { _ in
                showEditor = false
                Task { await vm.load() }
            }
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Commission Rules")
            .toolbar { addButton }
        }
    }

    private var regularLayout: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Commission Rules")
            .toolbar { addButton }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36)).foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Couldn't load rules")
                    .font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Text(err).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                Button("Try again") { Task { await vm.load() } }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.rules.isEmpty {
            VStack(spacing: BrandSpacing.md) {
                Image(systemName: "percent").font(.system(size: 48))
                    .foregroundStyle(.bizarreOnSurfaceMuted).accessibilityHidden(true)
                Text("No commission rules").font(.brandTitleMedium()).foregroundStyle(.bizarreOnSurface)
                Button("Add first rule") { showEditor = true }
                    .buttonStyle(.borderedProminent).tint(.bizarreOrange)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(vm.rules) { rule in
                    RuleRow(rule: rule)
                        .listRowBackground(Color.bizarreSurface1)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.delete(rule: rule) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                editingRule = rule
                                showEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.bizarreOrange)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ToolbarContentBuilder
    private var addButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                editingRule = nil
                showEditor = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add commission rule")
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

// MARK: - RuleRow

private struct RuleRow: View {
    let rule: CommissionRule

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "percent")
                .frame(width: 32)
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(title).font(.brandBodyLarge()).foregroundStyle(.bizarreOnSurface).lineLimit(1)
                Text(valueLabel).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                if let cap = rule.capAmount { Text("Cap: \(formatMoney(cap))").font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted) }
            }
            Spacer()
            Text(rule.ruleType.rawValue.capitalized)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm).padding(.vertical, BrandSpacing.xxs)
                .foregroundStyle(.bizarreOnSurface)
                .background(Color.bizarreSurface2, in: Capsule())
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(valueLabel). \(rule.ruleType.rawValue)")
    }

    private var title: String {
        [rule.role, rule.serviceCategory, rule.productCategory]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " / ")
            .ifEmpty("All")
    }

    private var valueLabel: String {
        switch rule.ruleType {
        case .percentage: return String(format: "%.1f%%", rule.value)
        case .flat: return formatMoney(rule.value)
        }
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// Expose api reference for sheet injection
private extension CommissionRulesListViewModel {
    var apiRef: APIClient { api }
}
