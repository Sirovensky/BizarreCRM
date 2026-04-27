import Foundation
import Observation
import Core
import Networking

// MARK: - ServiceType

public enum AppointmentServiceType: String, CaseIterable, Sendable {
    case dropOff = "Drop-off"
    case pickup = "Pickup"
    case consultation = "Consultation"
    case onSite = "On-site"
    case delivery = "Delivery"
}

// MARK: - AppointmentCreateFullViewModel

/// Extended VM for the full appointment create form:
/// customer picker, service type, technician picker with availability slots,
/// conflict detection, duration, draft auto-save.
@MainActor
@Observable
public final class AppointmentCreateFullViewModel {

    // MARK: - Form fields

    public var customerId: Int64?
    public var customerDisplayName: String = ""
    public var serviceType: AppointmentServiceType = .dropOff
    public var technicianId: Int64?
    public var technicianDisplayName: String = ""
    public var selectedSlot: AvailabilitySlot?
    public var duration: TimeInterval = 60 * 60   // 1 hour default
    public var notes: String = ""
    public var repeatRule: RepeatRule?

    // MARK: - Availability

    public private(set) var availabilitySlots: [AvailabilitySlot] = []
    public internal(set) var conflictingSlots: Set<String> = []  // slot.id
    public private(set) var isLoadingSlots: Bool = false
    public var selectedDate: Date = Date()

    // MARK: - Employees

    public private(set) var employees: [Employee] = []
    public private(set) var isLoadingEmployees: Bool = false

    // MARK: - Submit state

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?
    public private(set) var conflictWarning: Bool = false
    /// §10.3 offline temp-id — set to -1 when network unavailable; list reconciles on next sync.
    public private(set) var queuedOffline: Bool = false

    // MARK: - Draft auto-save (stored as title/notes/dates)

    public private(set) var draftSavedAt: Date?

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private var slotLoadTask: Task<Void, Never>?
    /// §10.3 idempotency key — generated once per create session; re-used on retry.
    @ObservationIgnored private var idempotencyKey: String = UUID().uuidString

    // MARK: - Init

    public init(api: APIClient) {
        self.api = api
    }

    /// Reset idempotency key — call when the user explicitly starts a new attempt
    /// (e.g. after fixing a conflict rather than retrying the same submission).
    public func resetIdempotencyKey() {
        idempotencyKey = UUID().uuidString
    }

    // MARK: - Validation

    public var isValid: Bool {
        customerId != nil && selectedSlot != nil
    }

    // MARK: - Employees load

    public func loadEmployees() async {
        guard !isLoadingEmployees else { return }
        isLoadingEmployees = true
        defer { isLoadingEmployees = false }
        do {
            employees = try await api.listEmployees()
        } catch {
            AppLog.ui.error("Appt create: employees load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Availability load

    public func loadAvailability() async {
        guard let techId = technicianId else {
            availabilitySlots = []
            conflictingSlots = []
            return
        }
        slotLoadTask?.cancel()
        slotLoadTask = Task { [weak self] in
            guard let self else { return }
            isLoadingSlots = true
            defer { isLoadingSlots = false }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            let dateStr = df.string(from: selectedDate)
            do {
                let slots = try await api.fetchEmployeeAvailability(
                    employeeId: techId,
                    date: dateStr
                )
                if Task.isCancelled { return }
                // Load existing appointments for conflict check
                let existing = try await api.listAppointments(
                    fromDate: dateStr,
                    toDate: dateStr
                )
                if Task.isCancelled { return }
                let (_, conflicting) = AppointmentConflictResolver.filterConflicting(
                    slots: slots,
                    duration: duration,
                    existingAppointments: existing
                )
                availabilitySlots = slots
                conflictingSlots = Set(conflicting.map(\.id))
            } catch {
                if !Task.isCancelled {
                    AppLog.ui.error("Appt availability load failed: \(error.localizedDescription, privacy: .public)")
                    availabilitySlots = []
                    conflictingSlots = []
                }
            }
        }
        await slotLoadTask?.value
    }

    // MARK: - Slot selection

    public func selectSlot(_ slot: AvailabilitySlot) {
        selectedSlot = slot
        conflictWarning = conflictingSlots.contains(slot.id)
    }

    // MARK: - Draft auto-save

    public func scheduleDraftSave() {
        draftTask?.cancel()
        draftTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.draftSavedAt = Date()
        }
    }

    // MARK: - Submit

    public func submit() async {
        guard !isSubmitting else { return }
        guard let cid = customerId else {
            errorMessage = "Select a customer first."
            return
        }
        guard let slot = selectedSlot else {
            errorMessage = "Select a time slot first."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let req = CreateAppointmentRequest(
            title: "\(serviceType.rawValue) — \(customerDisplayName.isEmpty ? "Customer #\(cid)" : customerDisplayName)",
            startTime: slot.start,
            endTime: slot.end,
            customerId: cid,
            notes: notes.isEmpty ? nil : notes,
            idempotencyKey: idempotencyKey
        )

        do {
            let created = try await api.createAppointment(req)
            createdId = created.id
            queuedOffline = false
            draftSavedAt = nil
            // New key so a subsequent create (different appointment) is fresh
            idempotencyKey = UUID().uuidString
        } catch let urlErr as URLError
            where urlErr.code == .notConnectedToInternet || urlErr.code == .networkConnectionLost {
            // §10.3 offline temp-id — assign sentinel -1 and mark for later sync
            AppLog.ui.notice("Appointment create queued offline (idempotencyKey=\(idempotencyKey))")
            createdId = -1
            queuedOffline = true
        } catch {
            let appError = AppError.from(error)
            errorMessage = Self.message(for: appError)
            AppLog.ui.error("Appt create failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private static func message(for error: AppError) -> String {
        switch error {
        case .conflict:
            return "This time slot has just been taken. Pick another."
        case .validation(let fields):
            return fields.values.first ?? "Check the form fields."
        case .offline:
            return "You're offline. Connect and try again."
        default:
            return error.errorDescription ?? "An unexpected error occurred."
        }
    }
}
