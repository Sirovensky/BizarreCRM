import SwiftUI
import DesignSystem

// MARK: - ApplyPresetSheet
//
// §47 Roles Capability Presets — sheet that lets the user browse the six
// canonical presets, preview what each one changes relative to the current
// role, and confirm application.
//
// Layout:
//   • Preset picker (top half) — scrollable row list with Liquid Glass header
//   • Diff preview (bottom half) — live PresetDiffView for the selected preset
//   • Confirm / Cancel toolbar actions

/// Modal sheet for browsing, previewing, and confirming a capability preset.
///
/// Present this sheet from any view that holds a `Role`.  On confirmation the
/// `onApply` closure is called with the chosen `RolePresetDescriptor`; the
/// caller is responsible for persisting the change.
public struct ApplyPresetSheet: View {

    // MARK: Callbacks

    /// Called when the user taps "Apply".  Receives the confirmed preset.
    public let onApply: (RolePresetDescriptor) -> Void

    // MARK: Inputs

    /// The role the preset will be applied to (used for diff calculation).
    public let currentRole: Role

    // MARK: State

    @State private var selectedPreset: RolePresetDescriptor? = RolePresetCatalog.all.first
    @Environment(\.dismiss) private var dismiss

    // MARK: Init

    public init(currentRole: Role, onApply: @escaping (RolePresetDescriptor) -> Void) {
        self.currentRole = currentRole
        self.onApply = onApply
    }

    // MARK: Computed

    private var diff: PresetCapabilityDiff? {
        selectedPreset?.diff(from: currentRole.capabilities)
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                presetPickerList
                Divider()
                diffPreviewPanel
            }
            .navigationTitle("Apply Preset to \"\(currentRole.name)\"")
            .inlineNavigationTitle()
            .toolbar { toolbarItems }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Preset picker

    @ViewBuilder
    private var presetPickerList: some View {
        List(RolePresetCatalog.all) { preset in
            PresetPickerRow(
                preset: preset,
                isSelected: selectedPreset?.id == preset.id
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedPreset = preset }
            .accessibilityAddTraits(selectedPreset?.id == preset.id ? .isSelected : [])
        }
        .listStyle(.plain)
        .frame(maxHeight: 260)
    }

    // MARK: - Diff preview panel

    @ViewBuilder
    private var diffPreviewPanel: some View {
        Group {
            if let preset = selectedPreset, let capDiff = diff {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        presetDescriptionHeader(preset)
                        Form {
                            PresetDiffView(diff: capDiff, presetName: preset.name)
                        }
                        .scrollDisabled(true)
                        .frame(minHeight: 100)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a Preset",
                    systemImage: "person.badge.key",
                    description: Text("Tap a preset above to preview changes")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func presetDescriptionHeader(_ preset: RolePresetDescriptor) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: presetIcon(for: preset.id))
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm),
                            tint: nil, interactive: false)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(preset.name)
                    .font(.headline)
                Text(preset.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(preset.name). \(preset.description)")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Apply") {
                if let preset = selectedPreset {
                    onApply(preset)
                    dismiss()
                }
            }
            .disabled(selectedPreset == nil)
            .fontWeight(.semibold)
            .accessibilityLabel(selectedPreset.map { "Apply \($0.name) preset" } ?? "Apply preset")
        }
    }

    // MARK: - Icon mapping

    private func presetIcon(for id: String) -> String {
        switch id {
        case "catalog.owner":     return "crown.fill"
        case "catalog.admin":     return "shield.lefthalf.filled"
        case "catalog.manager":   return "briefcase.fill"
        case "catalog.technician": return "wrench.and.screwdriver.fill"
        case "catalog.cashier":   return "creditcard.fill"
        case "catalog.read_only": return "eye.fill"
        default:                  return "person.badge.key.fill"
        }
    }
}

// MARK: - PresetPickerRow

private struct PresetPickerRow: View {

    let preset: RolePresetDescriptor
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(preset.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text("\(preset.capabilities.count) capabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                    .font(.body)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .contentShape(Rectangle())
    }
}
