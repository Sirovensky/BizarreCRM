import Foundation
import Observation
import Core
import Networking

// §4.2 — Device section edit: add new device to existing ticket, or update
// an existing device row. Wired to:
//   POST /api/v1/tickets/:id/devices     (new device)
//   PUT  /api/v1/tickets/devices/:id     (existing device update)
//   PUT  /api/v1/tickets/devices/:id/checklist (checklist save)

public enum DeviceEditMode: Sendable, Equatable {
    case add(ticketId: Int64)
    case edit(deviceId: Int64)
}

@MainActor
@Observable
public final class TicketDeviceEditViewModel {

    // MARK: - Form fields

    public var deviceName: String = ""
    public var imei: String = ""
    public var serial: String = ""
    public var securityCode: String = ""
    public var additionalNotes: String = ""
    public var priceText: String = ""
    public var checklist: [ChecklistItem] = DraftDevice.defaultChecklist()

    // MARK: - State flags

    public private(set) var isSubmitting: Bool = false
    public private(set) var isSavingChecklist: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var didSave: Bool = false

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let mode: DeviceEditMode

    public init(api: APIClient, mode: DeviceEditMode) {
        self.api = api
        self.mode = mode
    }

    /// Pre-populate from an existing device row (edit mode).
    public func populate(from device: TicketDetail.TicketDevice) {
        deviceName = device.deviceName ?? ""
        imei = device.imei ?? ""
        serial = device.serial ?? ""
        securityCode = device.securityCode ?? ""
        additionalNotes = device.additionalNotes ?? ""
        priceText = device.price.map { p in
            p == floor(p) ? String(Int(p)) : String(format: "%.2f", p)
        } ?? ""
    }

    // MARK: - Validation

    public var isValid: Bool {
        !deviceName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    public var price: Double {
        Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    // MARK: - Save

    public func save() async {
        guard !isSubmitting, isValid else {
            if !isValid { errorMessage = "Device name is required." }
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            switch mode {
            case .add(let ticketId):
                let req = AddTicketDeviceRequest(
                    deviceName: deviceName.trimmingCharacters(in: .whitespaces),
                    imei: nilIfEmpty(imei),
                    serial: nilIfEmpty(serial),
                    securityCode: nilIfEmpty(securityCode),
                    price: price,
                    additionalNotes: nilIfEmpty(additionalNotes)
                )
                let created = try await api.addTicketDevice(ticketId: ticketId, req)
                // After creating device, save checklist if any items are checked.
                if checklist.contains(where: { $0.checked }) {
                    _ = try await api.updateDeviceChecklist(deviceId: created.id, items: checklist)
                }

            case .edit(let deviceId):
                let req = UpdateTicketDeviceRequest(
                    deviceName: deviceName.trimmingCharacters(in: .whitespaces),
                    imei: nilIfEmpty(imei),
                    serial: nilIfEmpty(serial),
                    securityCode: nilIfEmpty(securityCode),
                    price: price.isZero ? nil : price,
                    additionalNotes: nilIfEmpty(additionalNotes)
                )
                _ = try await api.updateTicketDevice(deviceId: deviceId, req)
                // Always save checklist on edit.
                _ = try await api.updateDeviceChecklist(deviceId: deviceId, items: checklist)
            }

            didSave = true
        } catch {
            AppLog.ui.error("Device save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = AppError.from(error).errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Checklist helpers

    public func toggleChecklistItem(id: String) {
        checklist = checklist.map { item in
            if item.id == id {
                return ChecklistItem(id: item.id, label: item.label, checked: !item.checked)
            }
            return item
        }
    }

    // MARK: - Private

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
