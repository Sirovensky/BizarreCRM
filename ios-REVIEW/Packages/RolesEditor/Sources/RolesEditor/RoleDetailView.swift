import SwiftUI
import DesignSystem

// MARK: - RoleDetailView (iPhone — grouped capability Form)

/// iPhone detail: grouped capability rows per domain, Form+List with Toggle per capability.
/// Wired to a real RoleDetailViewModel — no placeholder stubs.
public struct RoleDetailView: View {

    @State private var viewModel: RoleDetailViewModel
    @State private var showPresetPicker = false
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: RoleDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Form {
            roleHeaderSection
            ForEach(viewModel.domainedCapabilities, id: \.domain) { group in
                Section(group.domain) {
                    ForEach(group.capabilities) { cap in
                        capabilityRow(cap)
                    }
                }
            }
            presetsSection
        }
        .navigationTitle(viewModel.role.name)
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.hasUnsavedChanges {
                    Button("Save") {
                        Task { await viewModel.save() }
                    }
                    .disabled(viewModel.isSaving)
                    .accessibilityLabel("Save capability changes")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                if viewModel.hasUnsavedChanges {
                    Button("Discard", role: .destructive) {
                        viewModel.discard()
                    }
                    .accessibilityLabel("Discard unsaved changes")
                }
            }
        }
        .sheet(isPresented: $showPresetPicker) {
            presetPickerSheet
        }
        .overlay(alignment: .bottom) {
            if let err = viewModel.errorMessage {
                Text(err)
                    .font(.footnote)
                    .padding()
                    .background(.red.opacity(0.85))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .accessibilityLabel("Error: \(err)")
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isSaving {
                ProgressView("Saving…")
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top)
            }
        }
    }

    // MARK: Header section

    @ViewBuilder
    private var roleHeaderSection: some View {
        Section {
            LabeledContent("Name", value: viewModel.role.name)
            if let preset = viewModel.role.preset {
                LabeledContent("Based on", value: preset
                    .replacingOccurrences(of: "preset.", with: "")
                    .capitalized)
            }
            LabeledContent(
                "Capabilities",
                value: "\(viewModel.role.capabilities.count) / \(CapabilityCatalog.all.count)"
            )
        }
    }

    // MARK: Capability row

    @ViewBuilder
    private func capabilityRow(_ cap: Capability) -> some View {
        let isOn = viewModel.has(capability: cap.id)
        Toggle(isOn: Binding(
            get: { isOn },
            set: { _ in viewModel.toggle(capability: cap.id) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.label)
                    .font(.subheadline)
                Text(cap.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityLabel("\(cap.label) for \(viewModel.role.name): \(isOn ? "on" : "off")")
        .accessibilityHint(cap.description)
        .accessibilityValue(isOn ? "enabled" : "disabled")
    }

    // MARK: Presets section

    @ViewBuilder
    private var presetsSection: some View {
        Section("Templates") {
            Button("Apply a preset template…") {
                showPresetPicker = true
            }
            .accessibilityLabel("Apply a preset template to this role")
        }
    }

    // MARK: Preset picker sheet

    @ViewBuilder
    private var presetPickerSheet: some View {
        NavigationStack {
            List(RolePresets.all, id: \.id) { preset in
                Button {
                    viewModel.applyPreset(preset)
                    showPresetPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Text("\(preset.capabilities.count) capabilities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel("\(preset.name), \(preset.capabilities.count) capabilities")
            }
            .navigationTitle("Choose Preset")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPresetPicker = false }
                }
            }
        }
    }
}
