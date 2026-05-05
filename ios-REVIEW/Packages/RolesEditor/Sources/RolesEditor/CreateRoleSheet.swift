import SwiftUI
import DesignSystem

// MARK: - CreateRoleSheet

/// Presented modally on both iPhone and iPad when the user taps the "+" button.
/// Lets the user name the role, add an optional description, and optionally
/// start from a built-in preset template.
public struct CreateRoleSheet: View {

    // MARK: Input callback

    /// Called on confirmation with (name, description, presetId?).
    public let onCreate: (String, String?, String?) -> Void

    // MARK: State

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedPreset: RolePreset? = nil
    @State private var showPresetPicker = false
    @Environment(\.dismiss) private var dismiss

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty }

    // MARK: Init

    public init(onCreate: @escaping (String, String?, String?) -> Void) {
        self.onCreate = onCreate
    }

    // MARK: Body

    public var body: some View {
        NavigationStack {
            Form {
                nameSection
                descriptionSection
                presetsSection
                if let preset = selectedPreset {
                    presetSummarySection(preset)
                }
            }
            .navigationTitle("New Role")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(
                            trimmedName,
                            desc.isEmpty ? nil : desc,
                            selectedPreset?.id
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showPresetPicker) {
                presetPickerSheet
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var nameSection: some View {
        Section("Role Name") {
            TextField("e.g. Lead Technician", text: $name)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Role name")
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        Section("Description (optional)") {
            TextField("Brief description of this role", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .accessibilityLabel("Role description")
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        Section("Start from Template") {
            Button {
                showPresetPicker = true
            } label: {
                HStack {
                    Text(selectedPreset?.name ?? "Choose a preset…")
                        .foregroundStyle(selectedPreset == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .accessibilityLabel(selectedPreset == nil ? "Choose a preset template" : "Selected preset: \(selectedPreset!.name)")
        }
    }

    @ViewBuilder
    private func presetSummarySection(_ preset: RolePreset) -> some View {
        Section {
            Label("\(preset.capabilities.count) capabilities will be seeded from \"\(preset.name)\"", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Clear preset") {
                selectedPreset = nil
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: Preset picker sheet

    @ViewBuilder
    private var presetPickerSheet: some View {
        NavigationStack {
            List(RolePresets.all, id: \.id) { preset in
                Button {
                    selectedPreset = preset
                    showPresetPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(preset.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedPreset?.id == preset.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text("\(preset.capabilities.count) capabilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Choose Template")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPresetPicker = false }
                }
            }
        }
    }
}
