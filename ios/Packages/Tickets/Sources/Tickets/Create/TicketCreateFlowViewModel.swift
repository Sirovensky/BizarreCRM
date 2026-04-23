import Foundation
import Observation
import Core
import Networking
import Customers

// §4.3 — Full-fidelity multi-step ticket create view model.
//
// Steps: Customer → Devices → Pricing → Assignee/Due → Review
//
// Wired end-to-end:
//   View ← TicketCreateFlowViewModel ← TicketRepository (create + status) ← APIClient
//
// Pricing model: subtotal = sum of device prices (each price = labor + parts
// entered inline). Discount applied globally as absolute dollars.
// Tax not collected in create path (line-level tax set server-side via tax_class).

/// A device being added during ticket create.
public struct DraftDevice: Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var deviceName: String = ""
    public var deviceType: String = ""
    public var imei: String = ""
    public var serial: String = ""
    public var securityCode: String = ""
    public var additionalNotes: String = ""
    public var price: Double = 0
    public var checklist: [ChecklistItem] = DraftDevice.defaultChecklist()
    public var serviceId: Int64? = nil
    public var serviceName: String = ""

    // Returns the default pre-conditions checklist for new devices.
    public static func defaultChecklist() -> [ChecklistItem] {
        [
            ChecklistItem(label: "Screen cracked", checked: false),
            ChecklistItem(label: "Water damage", checked: false),
            ChecklistItem(label: "Passcode provided", checked: false),
            ChecklistItem(label: "Battery swollen", checked: false),
            ChecklistItem(label: "SIM tray present", checked: false),
            ChecklistItem(label: "Accessories included", checked: false),
            ChecklistItem(label: "Backup completed", checked: false),
            ChecklistItem(label: "Device powers on", checked: true),
        ]
    }
}

/// Steps in the create flow.
public enum CreateFlowStep: Int, CaseIterable, Sendable {
    case customer = 0
    case devices  = 1
    case pricing  = 2
    case schedule = 3
    case review   = 4

    public var title: String {
        switch self {
        case .customer: return "Customer"
        case .devices:  return "Devices"
        case .pricing:  return "Pricing"
        case .schedule: return "Assignee & Due Date"
        case .review:   return "Review"
        }
    }
}

@MainActor
@Observable
public final class TicketCreateFlowViewModel {

    // MARK: - Step navigation

    public var currentStep: CreateFlowStep = .customer
    public var canGoBack: Bool { currentStep != .customer }
    public var canGoNext: Bool { stepValid }

    // MARK: - Customer step

    public var selectedCustomer: CustomerSummary?

    // MARK: - Devices step

    public var devices: [DraftDevice] = [DraftDevice()]

    // MARK: - Pricing step

    /// Global discount applied after summing per-device prices.
    public var discountText: String = ""
    public var discountReason: String = ""
    public var discountMode: DiscountMode = .absolute

    public enum DiscountMode: String, CaseIterable, Sendable {
        case absolute  = "$"
        case percent   = "%"
    }

    // Read-only computed totals
    public var subtotal: Double {
        devices.reduce(0) { $0 + $1.price }
    }

    public var discountAmount: Double {
        guard let raw = Double(discountText.replacingOccurrences(of: ",", with: ".")),
              raw > 0 else { return 0 }
        switch discountMode {
        case .absolute: return min(raw, subtotal)
        case .percent:  return min(raw / 100.0 * subtotal, subtotal)
        }
    }

    public var grandTotal: Double { max(0, subtotal - discountAmount) }

    // MARK: - Assignee / due-date step

    public var assignedEmployeeId: Int64?
    public var assignedEmployeeName: String = ""
    public var dueOn: String = ""   // YYYY-MM-DD
    public var urgency: String = ""
    public var source: String = ""
    public var referralSource: String = ""
    public var statusId: Int64?

    // MARK: - Submit state

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdTicketId: Int64?
    public private(set) var queuedOffline: Bool = false
    public private(set) var validationErrors: [String: String] = [:]

    // MARK: - Dependencies

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Navigation

    public func next() {
        guard stepValid, let next = nextStep else { return }
        currentStep = next
    }

    public func back() {
        guard let prev = prevStep else { return }
        currentStep = prev
    }

    // MARK: - Device management (immutable updates per §coding-style)

    public func addDevice() {
        devices = devices + [DraftDevice()]
    }

    public func removeDevice(at index: Int) {
        guard devices.count > 1 else { return }
        var updated = devices
        updated.remove(at: index)
        devices = updated
    }

    public func updateDevice(at index: Int, _ update: (inout DraftDevice) -> Void) {
        guard index < devices.count else { return }
        var updated = devices
        update(&updated[index])
        devices = updated
    }

    // MARK: - Checklist helpers

    public func toggleChecklistItem(deviceIndex: Int, itemId: String) {
        guard deviceIndex < devices.count else { return }
        var updated = devices
        let updatedItems = updated[deviceIndex].checklist.map { item -> ChecklistItem in
            if item.id == itemId {
                return ChecklistItem(id: item.id, label: item.label, checked: !item.checked)
            }
            return item
        }
        updated[deviceIndex].checklist = updatedItems
        devices = updated
    }

    // MARK: - Submit

    public func submit() async {
        guard !isSubmitting, let customer = selectedCustomer else {
            if selectedCustomer == nil { errorMessage = "Pick a customer first." }
            return
        }
        isSubmitting = true
        errorMessage = nil
        queuedOffline = false
        defer { isSubmitting = false }

        let req = buildCreateRequest(customerId: customer.id)

        do {
            let created = try await api.createTicket(req)
            createdTicketId = created.id
        } catch {
            let appError = AppError.from(error)
            if case .offline = appError {
                await enqueueOffline(req)
            } else if TicketOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Full ticket create failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = appError.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Validation per step

    public var stepValid: Bool {
        switch currentStep {
        case .customer: return selectedCustomer != nil
        case .devices:
            return !devices.isEmpty && devices.allSatisfy { !$0.deviceName.trimmingCharacters(in: .whitespaces).isEmpty }
        case .pricing:
            if !discountText.isEmpty {
                guard let v = Double(discountText.replacingOccurrences(of: ",", with: ".")), v >= 0 else {
                    return false
                }
                if discountMode == .percent, let v = Double(discountText.replacingOccurrences(of: ",", with: ".")), v > 100 {
                    return false
                }
            }
            return true
        case .schedule: return true
        case .review:   return true
        }
    }

    // MARK: - Private helpers

    private var nextStep: CreateFlowStep? {
        let all = CreateFlowStep.allCases
        guard let idx = all.firstIndex(of: currentStep), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    private var prevStep: CreateFlowStep? {
        let all = CreateFlowStep.allCases
        guard let idx = all.firstIndex(of: currentStep), idx > 0 else { return nil }
        return all[idx - 1]
    }

    private func buildCreateRequest(customerId: Int64) -> CreateTicketRequest {
        let newDevices = devices.map { d in
            CreateTicketRequest.NewDevice(
                deviceName: d.deviceName.trimmingCharacters(in: .whitespaces),
                imei: nilIfEmpty(d.imei),
                serial: nilIfEmpty(d.serial),
                additionalNotes: nilIfEmpty(d.additionalNotes),
                price: d.price
            )
        }
        return CreateTicketRequest(
            customerId: customerId,
            devices: newDevices,
            statusId: statusId,
            assignedTo: assignedEmployeeId
        )
    }

    private func enqueueOffline(_ req: CreateTicketRequest) async {
        do {
            let payload = try TicketOfflineQueue.encode(req)
            await TicketOfflineQueue.enqueue(op: "create", payload: payload)
            createdTicketId = PendingSyncTicketId
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Offline enqueue encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
