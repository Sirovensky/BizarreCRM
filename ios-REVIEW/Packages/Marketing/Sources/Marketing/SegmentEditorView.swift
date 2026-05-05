import SwiftUI
import Core
import DesignSystem
import Networking

public struct SegmentEditorView: View {
    @State private var vm: SegmentEditorViewModel
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool

    public init(api: APIClient, existingId: String? = nil) {
        _vm = State(wrappedValue: SegmentEditorViewModel(api: api))
        self.isNew = existingId == nil
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                formContent
            }
            .navigationTitle(isNew ? "New Segment" : "Edit Segment")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarItems }
        }
        .onChange(of: vm.savedSegment) { _, s in
            if s != nil { dismiss() }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            nameSection
            presetsSection
            rulesSection
            countSection
            if let err = vm.errorMessage {
                Section {
                    Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                }
                .listRowBackground(Color.bizarreError.opacity(0.1))
            }
        }
        .scrollContentBackground(.hidden)
        #if canImport(UIKit)
        .background(Color.bizarreSurfaceBase)
        #endif
    }

    // MARK: - Name

    private var nameSection: some View {
        Section("Segment name") {
            TextField("e.g. VIP Customers", text: $vm.name)
                .font(.brandBodyLarge())
                .accessibilityLabel("Segment name")
                .accessibilityIdentifier("marketing.segment.name")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Presets

    private var presetsSection: some View {
        Section("Presets") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.sm) {
                    ForEach(SegmentPresets.all, id: \.name) { preset in
                        Button {
                            withAnimation { vm.applyPreset(preset) }
                        } label: {
                            Text(preset.name)
                                .font(.brandLabelSmall())
                                .padding(.horizontal, BrandSpacing.md)
                                .padding(.vertical, BrandSpacing.xs)
                                .foregroundStyle(.bizarreOnSurface)
                                .background(Color.bizarreSurface2, in: Capsule())
                        }
                        .accessibilityLabel("Load preset: \(preset.name)")
                    }
                }
                .padding(.vertical, BrandSpacing.xs)
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Rules

    private var rulesSection: some View {
        Section {
            // Root operator
            HStack {
                Text("Match")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Picker("Logic", selection: Binding(
                    get: { vm.rootGroup.op },
                    set: { vm.setRootOp($0) }
                )) {
                    Text("ALL (AND)").tag("AND")
                    Text("ANY (OR)").tag("OR")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Rule logic")
            }

            // Individual rules
            ForEach(Array(vm.rootGroup.rules.enumerated()), id: \.offset) { idx, rule in
                if case .leaf(let f, let o, let v) = rule {
                    LeafRuleRow(
                        index: idx,
                        field: f,
                        op: o,
                        value: v,
                        onUpdate: { field, op, value in
                            vm.updateLeaf(at: idx, field: field, op: op, value: value)
                        },
                        onRemove: { vm.removeRule(at: idx) }
                    )
                } else if case .group(let g) = rule {
                    NestedGroupRow(group: g)
                }
            }

            // Add buttons
            HStack(spacing: BrandSpacing.sm) {
                Button {
                    withAnimation { vm.addLeaf() }
                } label: {
                    Label("Add rule", systemImage: "plus.circle")
                        .font(.brandBodyMedium())
                }
                .accessibilityIdentifier("marketing.segment.addRule")

                Spacer()

                Button {
                    withAnimation { vm.addGroup() }
                } label: {
                    Label("Add group", systemImage: "folder.badge.plus")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreTeal)
                }
                .accessibilityIdentifier("marketing.segment.addGroup")
            }
        } header: {
            Text("Rules")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Live count

    private var countSection: some View {
        Section("Live count") {
            HStack {
                if vm.isCountLoading {
                    ProgressView().scaleEffect(0.8)
                    Text("Calculating…").font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                } else if let count = vm.liveCount {
                    Image(systemName: "person.3.fill").foregroundStyle(.bizarreTeal).accessibilityHidden(true)
                    Text("\(count) matching contacts")
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("\(count) matching contacts")
                } else {
                    Text("Add rules to see count")
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
                Button {
                    Task { await vm.refreshCount() }
                } label: {
                    Image(systemName: "arrow.clockwise").accessibilityLabel("Refresh count")
                }
                .accessibilityIdentifier("marketing.segment.refreshCount")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if vm.isSaving {
                ProgressView()
            } else {
                Button("Save") {
                    Task { await vm.save() }
                }
                .disabled(vm.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("marketing.segment.save")
            }
        }
    }
}

// MARK: - Leaf rule row

private struct LeafRuleRow: View {
    let index: Int
    let field: String
    let op: String
    let value: String
    let onUpdate: (String, String, String) -> Void
    let onRemove: () -> Void

    @State private var currentField: String
    @State private var currentOp: String
    @State private var currentValue: String

    init(index: Int, field: String, op: String, value: String,
         onUpdate: @escaping (String, String, String) -> Void,
         onRemove: @escaping () -> Void) {
        self.index = index
        self.field = field
        self.op = op
        self.value = value
        self.onUpdate = onUpdate
        self.onRemove = onRemove
        _currentField = State(wrappedValue: field)
        _currentOp = State(wrappedValue: op)
        _currentValue = State(wrappedValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Picker("Field", selection: $currentField) {
                    ForEach(SegmentField.allCases, id: \.rawValue) { f in
                        Text(f.displayName).tag(f.rawValue)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Rule field")
                .onChange(of: currentField) { _, _ in emit() }

                Picker("Comparator", selection: $currentOp) {
                    ForEach(SegmentComparator.allCases, id: \.rawValue) { c in
                        Text(c.displayName).tag(c.rawValue)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Rule comparator")
                .onChange(of: currentOp) { _, _ in emit() }

                Button(role: .destructive) { onRemove() } label: {
                    Image(systemName: "trash").foregroundStyle(.bizarreError)
                }
                .accessibilityLabel("Remove rule \(index + 1)")
                .accessibilityIdentifier("marketing.segment.removeRule.\(index)")
            }

            TextField("Value", text: $currentValue)
                .textFieldStyle(.roundedBorder)
                .font(.brandBodyMedium())
                .accessibilityLabel("Rule value")
                .onChange(of: currentValue) { _, _ in emit() }
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rule \(index + 1): \(currentField) \(currentOp) \(currentValue)")
    }

    private func emit() {
        onUpdate(currentField, currentOp, currentValue)
    }
}

// MARK: - Nested group row (display only at root level)

private struct NestedGroupRow: View {
    let group: SegmentRuleGroup

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
            Text("Group (\(group.op))")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreTeal)
            Text("\(group.rules.count) rule\(group.rules.count == 1 ? "" : "s") inside")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .padding(.vertical, BrandSpacing.xs)
    }
}
