#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Device add/edit sheet.
//
// iPhone: sheet with .presentationDetents([.large]).
// iPad: same sheet; wide-format auto-detent keeps form comfortable.
//
// Wires to:
//   POST /api/v1/tickets/:id/devices     (add mode)
//   PUT  /api/v1/tickets/devices/:id     (edit mode)
//   PUT  /api/v1/tickets/devices/:id/checklist (inline after save)

public struct TicketDeviceEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketDeviceEditViewModel
    private let title: String
    private let onSaved: () -> Void

    public init(api: APIClient, mode: DeviceEditMode, onSaved: @escaping () -> Void = {}) {
        _vm = State(wrappedValue: TicketDeviceEditViewModel(api: api, mode: mode))
        self.onSaved = onSaved
        switch mode {
        case .add: title = "Add Device"
        case .edit: title = "Edit Device"
        }
    }

    /// Convenience init for editing an existing device row.
    public init(api: APIClient, device: TicketDetail.TicketDevice, onSaved: @escaping () -> Void = {}) {
        let vm = TicketDeviceEditViewModel(api: api, mode: .edit(deviceId: device.id))
        vm.populate(from: device)
        _vm = State(wrappedValue: vm)
        self.onSaved = onSaved
        title = "Edit Device"
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Device info") {
                    TextField("Device name (required)", text: $vm.deviceName)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Device name, required")

                    TextField("IMEI", text: $vm.imei)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .accessibilityLabel("IMEI number")

                    TextField("Serial number", text: $vm.serial)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Serial number")

                    TextField("Security code / pattern", text: $vm.securityCode)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Security code or unlock pattern")
                }

                Section("Service notes") {
                    TextField("Issue description…", text: $vm.additionalNotes, axis: .vertical)
                        .lineLimit(2...5)
                        .accessibilityLabel("Device issue description")
                }

                Section("Pricing") {
                    TextField("Price (USD)", text: $vm.priceText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Repair price in US dollars")
                }

                Section("Pre-conditions intake") {
                    ForEach(vm.checklist) { item in
                        Button {
                            vm.toggleChecklistItem(id: item.id)
                        } label: {
                            HStack {
                                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(item.checked ? .bizarreOrange : .bizarreOnSurfaceMuted)
                                Text(item.label)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.label)
                        .accessibilityValue(item.checked ? "checked" : "unchecked")
                        .accessibilityHint("Toggle this checklist item")
                    }
                }

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.bizarreError)
                            .font(.brandBodyMedium())
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel device edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.save()
                            if vm.didSave {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel(vm.isSubmitting ? "Saving device" : "Save device")
                }
            }
        }
        .presentationDetents([.large])
    }
}
#endif
