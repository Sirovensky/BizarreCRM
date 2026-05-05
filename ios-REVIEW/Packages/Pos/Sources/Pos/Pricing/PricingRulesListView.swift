#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - PricingRulesListViewModel

/// §16 — ViewModel for Settings → Pricing rules admin screen.
///
/// Rules are displayed sorted by `priority` (ascending). The admin
/// can drag-to-reorder rows; on drop the priorities are reassigned
/// 0, 1, 2, … and saved to the server via `PATCH /pos/pricing-rules/order`.
///
/// API containment: all server calls go through `PricingRulesRepository`.
@MainActor
@Observable
public final class PricingRulesListViewModel {

    // MARK: - State

    public enum LoadState: Equatable {
        case idle, loading, loaded, error(String)
    }

    public private(set) var rules: [PricingRule] = []
    public private(set) var loadState: LoadState = .idle
    public private(set) var isReordering: Bool = false

    private let repository: any PricingRulesRepository

    public init(repository: any PricingRulesRepository) {
        self.repository = repository
    }

    public convenience init(api: any APIClient) {
        self.init(repository: PricingRulesRepositoryImpl(api: api))
    }

    // MARK: - Actions

    public func load() async {
        loadState = .loading
        do {
            rules = try await repository.listRules()
            loadState = .loaded
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Reorder on drag-drop: `IndexSet` from `.onMove` callback, `Int` is destination.
    /// Immediately updates local order and dispatches server sync.
    public func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        reassignPriorities()
        Task { await syncOrder() }
    }

    public func delete(rule: PricingRule) async {
        rules.removeAll { $0.id == rule.id }
        do {
            try await repository.deleteRule(id: rule.id)
        } catch {
            // Reload to re-sync if delete failed.
            await load()
        }
    }

    public func toggleEnabled(rule: PricingRule) async {
        guard let idx = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var updated = rule
        updated.enabled = !rule.enabled
        rules[idx] = updated
        do {
            try await repository.updateRule(updated)
        } catch {
            // Revert on failure.
            rules[idx] = rule
        }
    }

    public func upsert(_ rule: PricingRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            var newRule = rule
            newRule.priority = rules.count
            rules.append(newRule)
        }
        Task { await syncOrder() }
    }

    // MARK: - Private

    private func reassignPriorities() {
        rules = rules.enumerated().map { idx, rule in
            var r = rule; r.priority = idx; return r
        }
    }

    private func syncOrder() async {
        isReordering = true
        defer { isReordering = false }
        do {
            let orderedIds = rules.map(\.id)
            try await repository.reorderRules(orderedIds: orderedIds)
        } catch {
            // Non-fatal: next app launch will re-fetch from server.
            AppLog.pos.warning("PricingRulesListViewModel: reorder sync failed: \(error)")
        }
    }
}

// MARK: - PricingRulesListView

/// Settings → Pricing rules — drag-to-reorder list with inline enable/disable toggle.
///
/// iPhone: `NavigationStack` with full-width list.
/// iPad: left column in a `NavigationSplitView` paired with a detail editor.
public struct PricingRulesListView: View {

    @State private var vm: PricingRulesListViewModel
    @State private var editingRule: PricingRule? = nil
    @State private var showingCreate: Bool = false

    public init(vm: PricingRulesListViewModel) {
        _vm = State(initialValue: vm)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                ipadLayout
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showingCreate) {
            editorSheet(mode: .create)
        }
        .sheet(item: $editingRule) { rule in
            editorSheet(mode: .edit(rule))
        }
    }

    // MARK: - iPhone layout

    private var phoneLayout: some View {
        NavigationStack {
            ruleListContent
                .navigationTitle("Pricing Rules")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
    }

    // MARK: - iPad layout

    private var ipadLayout: some View {
        NavigationStack {
            ruleListContent
                .navigationTitle("Pricing Rules")
                .toolbar { toolbarContent }
        }
    }

    // MARK: - List content

    @ViewBuilder
    private var ruleListContent: some View {
        switch vm.loadState {
        case .loading:
            ProgressView("Loading rules…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading pricing rules")

        case .error(let msg):
            ContentUnavailableView(msg, systemImage: "exclamationmark.triangle")

        default:
            if vm.rules.isEmpty {
                ContentUnavailableView(
                    "No Pricing Rules",
                    systemImage: "tag.slash",
                    description: Text("Tap + to create your first rule.")
                )
            } else {
                List {
                    Section {
                        ForEach(vm.rules) { rule in
                            PricingRuleRow(rule: rule,
                                          onToggle: { Task { await vm.toggleEnabled(rule: rule) } },
                                          onEdit: { editingRule = rule })
                                .listRowBackground(Color.bizarreSurface1)
                                .hoverEffect(.highlight)
                                .contextMenu {
                                    Button { editingRule = rule } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        Task { await vm.delete(rule: rule) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                        .onMove { source, destination in
                            vm.move(from: source, to: destination)
                        }
                        .onDelete { offsets in
                            for idx in offsets {
                                Task { await vm.delete(rule: vm.rules[idx]) }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Rules evaluated in order — drag to reorder")
                                .font(.brandLabelSmall())
                                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                            Spacer()
                            if vm.isReordering {
                                ProgressView().scaleEffect(0.6)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase)
                .environment(\.editMode, .constant(.active))
                .accessibilityIdentifier("pricingRules.list")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingCreate = true
            } label: {
                Label("New Rule", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .accessibilityIdentifier("pricingRules.addButton")
        }
    }

    // MARK: - Editor sheet

    private func editorSheet(mode: PricingRuleEditorViewModel.Mode) -> some View {
        PricingRuleEditorView(mode: mode) { [vm] rule in
            vm.upsert(rule)
        }
    }
}

// MARK: - PricingRuleRow

private struct PricingRuleRow: View {
    let rule: PricingRule
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            // Priority badge
            Text("#\(rule.priority + 1)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name)
                    .font(.brandLabelLarge())
                    .foregroundStyle(rule.enabled ? Color.bizarreOnSurface : Color.bizarreOnSurfaceMuted)
                Text(rule.type.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }

            Spacer()

            // Enabled toggle
            Toggle("", isOn: Binding(get: { rule.enabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(Color.bizarreSuccess)
                .accessibilityLabel(rule.enabled ? "Disable \(rule.name)" : "Enable \(rule.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), \(rule.type.displayName), priority \(rule.priority + 1), \(rule.enabled ? "enabled" : "disabled")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - PricingRuleType display name

extension PricingRuleType {
    var displayName: String {
        switch self {
        case .bulkBundle:      return "Bulk bundle"
        case .bogo:            return "Buy X get Y free"
        case .tieredVolume:    return "Tiered volume"
        case .segmentPrice:    return "Customer segment"
        case .locationOverride: return "Location override"
        case .promotionWindow: return "Promotion window"
        }
    }
}

#endif
