import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §43.5 Device Template Editor View

/// Full editor for creating or updating a device template.
/// Phone: NavigationStack + sheet. iPad: used as detail column in DeviceTemplateListView.
@MainActor
public struct DeviceTemplateEditorView: View {
    @State private var vm: DeviceTemplateEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private let onSaved: (DeviceTemplate) -> Void

    public init(api: APIClient, editingTemplate: DeviceTemplate? = nil, onSaved: @escaping (DeviceTemplate) -> Void) {
        self.onSaved = onSaved
        _vm = State(wrappedValue: DeviceTemplateEditorViewModel(api: api, editingTemplate: editingTemplate))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            formContent
        }
        .navigationTitle(vm.isEditing ? "Edit Template" : "New Template")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("templateEditor.cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                if vm.isSaving {
                    ProgressView().tint(.bizarreOrange)
                } else {
                    Button("Save") {
                        Task { await saveAndDismiss() }
                    }
                    .bold()
                    .accessibilityIdentifier("templateEditor.save")
                }
            }
        }
        .onChange(of: vm.savedTemplate) { _, new in
            guard let saved = new else { return }
            onSaved(saved)
            dismiss()
        }
        .task { await vm.loadFamilies() }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            // Model name
            Section {
                TextField("Model name (required)", text: $vm.name)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Device model name")
                    .accessibilityIdentifier("templateEditor.name")
            } header: {
                Text("Device")
            } footer: {
                if vm.validationErrors.contains(.nameEmpty) {
                    Text(DeviceTemplateValidator.ValidationError.nameEmpty.errorDescription!)
                        .foregroundStyle(.bizarreError)
                } else if vm.validationErrors.contains(.nameTooLong) {
                    Text(DeviceTemplateValidator.ValidationError.nameTooLong.errorDescription!)
                        .foregroundStyle(.bizarreError)
                }
            }
            .listRowBackground(Color.bizarreSurface1)

            // Family picker
            Section {
                Picker("Family", selection: $vm.family) {
                    ForEach(vm.availableFamilies, id: \.self) { fam in
                        Text(fam).tag(fam)
                    }
                    Text("Other").tag("Other")
                }
                .accessibilityLabel("Device family")
                .accessibilityIdentifier("templateEditor.family")
                .onChange(of: vm.family) { _, new in
                    vm.isCustomFamily = (new == "Other")
                }

                if vm.isCustomFamily {
                    TextField("Custom family", text: $vm.customFamily)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                        .accessibilityLabel("Custom device family name")
                        .accessibilityIdentifier("templateEditor.customFamily")
                }
            } footer: {
                if vm.validationErrors.contains(.familyEmpty) {
                    Text(DeviceTemplateValidator.ValidationError.familyEmpty.errorDescription!)
                        .foregroundStyle(.bizarreError)
                }
            }
            .listRowBackground(Color.bizarreSurface1)

            // Year
            Section {
                TextField("Year (optional)", text: $vm.year)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel("Device year")
                    .accessibilityIdentifier("templateEditor.year")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Conditions (multi-select chips inside Form)
            Section("Conditions") {
                conditionChips
            }
            .listRowBackground(Color.bizarreSurface1)

            // Services
            Section {
                ForEach(vm.inlineServices.indices, id: \.self) { idx in
                    NewServiceInlineForm(
                        index: idx,
                        service: vm.inlineServices[idx],
                        onNameChange: { vm.updateInlineService(at: idx, name: $0) },
                        onPriceChange: { vm.updateInlineService(at: idx, rawPrice: $0) },
                        onDescriptionChange: { vm.updateInlineService(at: idx, description: $0) },
                        onRemove: { vm.removeInlineService(at: idx) }
                    )
                    .listRowInsets(EdgeInsets(top: BrandSpacing.xs, leading: BrandSpacing.xs, bottom: BrandSpacing.xs, trailing: BrandSpacing.xs))
                }

                Button {
                    vm.addInlineService()
                } label: {
                    Label("Add Service", systemImage: "plus.circle")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityIdentifier("templateEditor.addService")
            } header: {
                Text("Services")
            }
            .listRowBackground(Color.bizarreSurface1)

            // Validation errors
            if !vm.validationErrors.isEmpty {
                Section {
                    ForEach(Array(vm.validationErrors.enumerated()), id: \.offset) { _, err in
                        Text(err.errorDescription ?? "")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreError)
                    }
                }
                .listRowBackground(Color.bizarreError.opacity(0.08))
            }

            // Save error
            if let err = vm.saveError {
                Section {
                    Text(err)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreError)
                        .accessibilityLabel("Save error: \(err)")
                }
                .listRowBackground(Color.bizarreError.opacity(0.08))
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Condition chips

    private var conditionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(DeviceCondition.allCases) { condition in
                    let isSelected = vm.selectedConditionIds.contains(condition.id)
                    Button {
                        vm.toggleCondition(condition.id)
                    } label: {
                        Text(condition.label)
                            .font(.brandLabelLarge())
                            .padding(.horizontal, BrandSpacing.md)
                            .padding(.vertical, BrandSpacing.xs)
                            .foregroundStyle(isSelected ? .bizarreOnOrange : .bizarreOnSurface)
                            .background(
                                isSelected ? Color.bizarreOrange : Color.bizarreSurface2,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityLabel("\(condition.label)\(isSelected ? ", selected" : "")")
                    .accessibilityIdentifier("templateEditor.condition.\(condition.id)")
                }
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .listRowInsets(EdgeInsets())
        .accessibilityLabel("Device conditions")
    }

    // MARK: - Actions

    private func saveAndDismiss() async {
        await vm.save()
    }
}
