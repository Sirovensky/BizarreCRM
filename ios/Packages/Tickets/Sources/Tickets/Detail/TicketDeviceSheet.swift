#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// §4.2 — Add / edit a device on a ticket.
//
// Add:  POST /api/v1/tickets/:id/devices   body: { name, imei, serial, security_code, additional_notes }
// Edit: PUT  /api/v1/tickets/devices/:deviceId
//
// Server routes confirmed: tickets.routes.ts
// POST /tickets/:id/devices (line 2300±)
// PUT  /tickets/devices/:deviceId (line 2350±)

// MARK: - ViewModel

@MainActor
@Observable
final class TicketDeviceSheetViewModel {

    var name: String
    var imei: String
    var serial: String
    var securityCode: String
    var additionalNotes: String
    var price: String

    private(set) var isSaving: Bool = false
    private(set) var savedSuccessfully: Bool = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let api: APIClient
    let ticketId: Int64
    let existingDeviceId: Int64?   // nil = add mode

    var isAddMode: Bool { existingDeviceId == nil }

    init(api: APIClient, ticketId: Int64, existingDevice: TicketDetail.TicketDevice? = nil) {
        self.api = api
        self.ticketId = ticketId
        self.existingDeviceId = existingDevice?.id
        self.name = existingDevice?.displayName ?? ""
        self.imei = existingDevice?.imei ?? ""
        self.serial = existingDevice?.serial ?? ""
        self.securityCode = existingDevice?.securityCode ?? ""
        self.additionalNotes = existingDevice?.additionalNotes ?? ""
        let p = existingDevice?.price ?? 0
        self.price = p > 0 ? String(format: "%.2f", p) : ""
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        struct DeviceBody: Encodable, Sendable {
            let name: String
            let imei: String?
            let serial: String?
            let securityCode: String?
            let additionalNotes: String?
            let price: Double?
            enum CodingKeys: String, CodingKey {
                case name, imei, serial
                case securityCode = "security_code"
                case additionalNotes = "additional_notes"
                case price
            }
        }

        let body = DeviceBody(
            name: name.trimmingCharacters(in: .whitespaces),
            imei: imei.isEmpty ? nil : imei,
            serial: serial.isEmpty ? nil : serial,
            securityCode: securityCode.isEmpty ? nil : securityCode,
            additionalNotes: additionalNotes.isEmpty ? nil : additionalNotes,
            price: Double(price.replacingOccurrences(of: ",", with: "."))
        )

        do {
            if let deviceId = existingDeviceId {
                _ = try await api.put(
                    "/api/v1/tickets/devices/\(deviceId)",
                    body: body,
                    as: TicketDetail.TicketDevice.self
                )
            } else {
                _ = try await api.post(
                    "/api/v1/tickets/\(ticketId)/devices",
                    body: body,
                    as: TicketDetail.TicketDevice.self
                )
            }
            savedSuccessfully = true
        } catch {
            AppLog.ui.error("Device save failed (ticket \(self.ticketId)): \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

/// §4.2 — Sheet for adding a new device or editing an existing one.
public struct TicketDeviceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketDeviceSheetViewModel
    let onSaved: () -> Void

    public init(api: APIClient, ticketId: Int64, existingDevice: TicketDetail.TicketDevice? = nil, onSaved: @escaping () -> Void) {
        _vm = State(wrappedValue: TicketDeviceSheetViewModel(
            api: api,
            ticketId: ticketId,
            existingDevice: existingDevice
        ))
        self.onSaved = onSaved
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                Form {
                    Section("Device info") {
                        TextField("Device name (e.g. iPhone 14 Pro)", text: $vm.name)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Device name, required")

                        TextField("IMEI", text: $vm.imei)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityLabel("IMEI number")

                        TextField("Serial number", text: $vm.serial)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .accessibilityLabel("Serial number")

                        TextField("Security code / pattern", text: $vm.securityCode)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Device security code or screen pattern")
                    }

                    Section("Notes & pricing") {
                        TextField("Issue / customer comments…", text: $vm.additionalNotes, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityLabel("Device issue or customer comment")

                        TextField("Repair price (USD)", text: $vm.price)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Repair price in US dollars")
                    }

                    if let err = vm.errorMessage {
                        Section {
                            Text(err)
                                .font(.brandBodyMedium())
                                .foregroundStyle(.bizarreError)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(vm.isAddMode ? "Add Device" : "Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel device edit")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task { await vm.save() }
                    }
                    .disabled(!vm.canSave || vm.isSaving)
                    .fontWeight(.semibold)
                    .accessibilityLabel("Save device")
                }
            }
        }
        .onChange(of: vm.savedSuccessfully) { _, success in
            if success { onSaved(); dismiss() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
#endif
