import SwiftUI
import DesignSystem
import Observation

// MARK: - BundleRuleEditorViewModel

@MainActor
@Observable
public final class BundleRuleEditorViewModel {

    // MARK: - State

    public private(set) var rules: [BundleRule]

    // MARK: - Init

    public init(rules: [BundleRule] = [.ticketsPerCustomer, .invoicesPerDay]) {
        self.rules = rules
    }

    // MARK: - Mutations (immutable-pattern: return new copies stored back)

    public func addRule(_ rule: BundleRule) {
        rules = rules + [rule]
    }

    public func removeRule(at offsets: IndexSet) {
        rules = rules.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)
    }

    public func moveRule(from source: IndexSet, to destination: Int) {
        var mutable = rules
        mutable.move(fromOffsets: source, toOffset: destination)
        rules = mutable
    }

    public func toggleRule(id: String) {
        rules = rules.map { r in
            r.id == id ? r.withEnabled(!r.isEnabled) : r
        }
    }

    public func updateRule(_ updated: BundleRule) {
        rules = rules.map { r in r.id == updated.id ? updated : r }
    }

    // MARK: - New-rule builder

    /// Returns a fresh rule with default criteria for the given category.
    public func buildNewRule(
        name: String,
        category: EventCategory?,
        grouping: BundleRuleGrouping,
        lowPriorityOnly: Bool
    ) -> BundleRule {
        BundleRule(
            name: name,
            criteria: BundleRuleCriteria(
                category: category,
                lowPriorityOnly: lowPriorityOnly
            ),
            grouping: grouping
        )
    }
}

// MARK: - BundleRuleEditor

/// Full CRUD editor for user-defined bundle rules.
/// iPhone: single-column List with swipe-to-delete + drag reorder.
/// iPad: split: sidebar = rule list, detail = rule form.
public struct BundleRuleEditor: View {

    @State private var vm: BundleRuleEditorViewModel
    @State private var presentingAddSheet = false
    @State private var selectedRuleID: String?

    let onSave: ([BundleRule]) -> Void

    public init(
        viewModel: BundleRuleEditorViewModel = BundleRuleEditorViewModel(),
        onSave: @escaping ([BundleRule]) -> Void = { _ in }
    ) {
        _vm = State(wrappedValue: viewModel)
        self.onSave = onSave
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            ruleList
        }
        .navigationTitle("Bundle Rules")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { toolbarContent }
        .sheet(isPresented: $presentingAddSheet) {
            AddBundleRuleSheet { newRule in
                vm.addRule(newRule)
                presentingAddSheet = false
            }
        }
    }

    // MARK: - Rule list

    @ViewBuilder
    private var ruleList: some View {
        List {
            if vm.rules.isEmpty {
                emptyState
            } else {
                rulesSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var rulesSection: some View {
        Section {
            ForEach(vm.rules) { rule in
                BundleRuleRow(rule: rule) {
                    vm.toggleRule(id: rule.id)
                }
                .listRowBackground(Color.bizarreSurface1)
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }
            .onDelete(perform: vm.removeRule)
            .onMove(perform: vm.moveRule)
        } header: {
            Text("Rules are applied in order — first match wins.")
                .font(.system(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .textCase(nil)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(spacing: BrandSpacing.base) {
                Image(systemName: "tray.2")
                    .font(.system(size: 36))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text("No bundle rules yet.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Text("Tap + to create a rule like \"bundle all invoices per day\".")
                    .font(.system(size: 14))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(BrandSpacing.xl)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { onSave(vm.rules) }
                .fontWeight(.semibold)
                .accessibilityLabel("Save bundle rules")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                presentingAddSheet = true
            } label: {
                Label("Add rule", systemImage: "plus")
            }
            .accessibilityLabel("Add new bundle rule")
            #if os(macOS)
            .keyboardShortcut("n", modifiers: [.command])
            #endif
        }
        #if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
            EditButton()
        }
        #endif
    }
}

// MARK: - BundleRuleRow

private struct BundleRuleRow: View {
    let rule: BundleRule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: iconName)
                .foregroundStyle(rule.isEnabled ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(rule.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.bizarreOnSurface)

                Text(summaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { rule.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                .tint(.bizarreOrange)
                .accessibilityLabel(rule.isEnabled ? "Rule enabled" : "Rule disabled")
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.name), \(summaryText), \(rule.isEnabled ? "enabled" : "disabled")")
    }

    private var iconName: String {
        switch rule.grouping {
        case .all:      return "square.stack.3d.up.fill"
        case .byEntity: return "person.crop.square.filled.and.at.rectangle"
        case .byDay:    return "calendar"
        }
    }

    private var summaryText: String {
        var parts = [String]()
        if let cat = rule.criteria.category { parts.append(cat.rawValue) }
        if rule.criteria.lowPriorityOnly { parts.append("low priority only") }
        parts.append("group \(rule.grouping.displayName.lowercased())")
        return parts.joined(separator: " · ")
    }
}

// MARK: - AddBundleRuleSheet

/// Lightweight form for adding a new rule.
private struct AddBundleRuleSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var name          = ""
    @State private var category: EventCategory? = nil
    @State private var grouping      = BundleRuleGrouping.all
    @State private var lowPrioOnly   = false

    let onAdd: (BundleRule) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                form
            }
            .navigationTitle("New Rule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { commitAdd() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var form: some View {
        List {
            Section("Rule Name") {
                TextField("e.g. Tickets per customer", text: $name)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("Rule name")
            }

            Section("Filter") {
                Picker("Category", selection: $category) {
                    Text("Any category").tag(Optional<EventCategory>.none)
                    ForEach(EventCategory.allCases, id: \.rawValue) { cat in
                        Text(cat.rawValue).tag(Optional(cat))
                    }
                }
                .listRowBackground(Color.bizarreSurface1)

                Toggle("Low priority only", isOn: $lowPrioOnly)
                    .tint(.bizarreOrange)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("Restrict to low priority notifications only")
            }

            Section("Group By") {
                Picker("Grouping", selection: $grouping) {
                    ForEach(BundleRuleGrouping.allCases, id: \.rawValue) { g in
                        Text(g.displayName).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    private func commitAdd() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let rule = BundleRule(
            name: trimmed,
            criteria: BundleRuleCriteria(category: category, lowPriorityOnly: lowPrioOnly),
            grouping: grouping
        )
        onAdd(rule)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        BundleRuleEditor()
    }
}
#endif
