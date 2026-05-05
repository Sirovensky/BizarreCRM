#if canImport(UIKit)
import SwiftUI
import DesignSystem

// §5.7 — Add-asset form sheet with device template picker + serial/IMEI fields.
// Liquid Glass on the navigation chrome (toolbar buttons).

struct AddAssetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var vm: CustomerAssetsViewModel

    // Common device types for the picker template.
    private static let deviceTemplates: [String] = [
        "Phone", "Tablet", "Laptop", "Desktop",
        "Smart Watch", "TV", "Gaming Console", "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    TextField("Name *", text: $vm.addName)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Asset name (required)")

                    Picker("Type", selection: $vm.addDeviceType) {
                        Text("Select…").tag("")
                        ForEach(Self.deviceTemplates, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }
                    .accessibilityLabel("Device type")

                    TextField("Color", text: $vm.addColor)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Device color")
                }

                Section("Identifiers") {
                    TextField("Serial number", text: $vm.addSerial)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityLabel("Serial number")

                    TextField("IMEI", text: $vm.addImei)
                        .keyboardType(.numberPad)
                        .accessibilityLabel("IMEI number")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $vm.addNotes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Asset notes")
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                    }
                }
            }
            .navigationTitle("Add Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .brandGlass(.clear, in: Capsule(), interactive: true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            let ok = await vm.addAsset()
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!vm.isAddFormValid || vm.isSaving)
                    .brandGlass(.regular, in: Capsule(), tint: .bizarreOrange, interactive: true)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
