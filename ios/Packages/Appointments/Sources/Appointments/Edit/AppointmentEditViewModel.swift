import Foundation
import Observation
import Core
import Networking

// MARK: - AppointmentEditViewModel

/// View-model for the appointment edit / reschedule screen.
///
/// Pre-populates form fields from an existing `Appointment` and submits a
/// `PUT /api/v1/leads/appointments/:id` with only the changed fields.
@MainActor
@Observable
public final class AppointmentEditViewModel {

    // MARK: - Form fields

    public var title: String
    public var technicianId: Int64?
    public var technicianDisplayName: String = ""
    public var selectedDate: Date
    public var selectedSlot: AvailabilitySlot?
    public var duration: TimeInterval
    public var serviceType: AppointmentServiceType
    public var notes: String

    // MARK: - Availability

    public private(set) var availabilitySlots: [AvailabilitySlot] = []
    public internal(set) var conflictingSlots: Set<String> = []
    public private(set) var isLoadingSlots: Bool = false

    // MARK: - Employees

    public private(set) var employees: [Employee] = []
    public private(set) var isLoadingEmployees: Bool = false

    // MARK: - Submit state

    public private(set) var isSubmitting: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var updatedAppointment: Appointment?
    public private(set) var conflictWarning: Bool = false

    // MARK: - Source

    public let appointment: Appointment

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var slotLoadTask: Task<Void, Never>?

    // MARK: - Init

    public init(appointment: Appointment, api: APIClient) {
        self.appointment = appointment
        self.api = api

        // Pre-populate from existing row
        title = appointment.title ?? ""
        technicianId = appointment.assignedId
        notes = appointment.notes ?? ""

        // Parse existing start time → Date for DatePicker seed
        if let raw = appointment.startTime, let parsed = Self.parseDate(raw) {
            selectedDate = parsed
            let interval = appointment.durationInterval ?? 3600
            duration = interval
        } else {
            selectedDate = Date()
            duration = 3600
        }

        // Map status/title back to service type if possible
        serviceType = AppointmentServiceType.allCases.first {
            appointment.title?.contains($0.rawValue) == true
        } ?? .dropOff
    }

    // MARK: - Validation

    public var isValid: Bool {
        !title.isEmpty
    }

    // MARK: - Employees load

    public func loadEmployees() async {
        guard !isLoadingEmployees else { return }
        isLoadingEmployees = true
        defer { isLoadingEmployees = false }
        do {
            employees = try await api.listEmployees()
        } catch {
            AppLog.ui.error("Appt edit: employees load failed: \(error.localizedDescription, privacy: .public)")
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
                let slots = try await api.fetchEmployeeAvailability(employeeId: techId, date: dateStr)
                if Task.isCancelled { return }
                let existing = try await api.listAppointments(fromDate: dateStr, toDate: dateStr)
                if Task.isCancelled { return }
                // Exclude the appointment being edited from conflict check
                let others = existing.filter { $0.id != appointment.id }
                let (_, conflicting) = AppointmentConflictResolver.filterConflicting(
                    slots: slots,
                    duration: duration,
                    existingAppointments: others
                )
                availabilitySlots = slots
                conflictingSlots = Set(conflicting.map(\.id))
            } catch {
                if !Task.isCancelled {
                    AppLog.ui.error("Appt edit availability load failed: \(error.localizedDescription, privacy: .public)")
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

    // MARK: - Submit

    public func submit() async {
        guard !isSubmitting else { return }
        guard isValid else {
            errorMessage = "Title cannot be empty."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Build start/end from selected slot if chosen, else keep original
        let startTime: String?
        let endTime: String?
        if let slot = selectedSlot {
            startTime = slot.start
            let fmt = ISO8601DateFormatter()
            if let s = fmt.date(from: slot.start) {
                endTime = fmt.string(from: s.addingTimeInterval(duration))
            } else {
                endTime = slot.end
            }
        } else {
            startTime = nil
            endTime = nil
        }

        let req = UpdateAppointmentRequest(
            title: title,
            startTime: startTime,
            endTime: endTime,
            assignedTo: technicianId,
            status: nil,
            notes: notes.isEmpty ? nil : notes
        )

        do {
            let updated = try await api.updateAppointment(id: appointment.id, req)
            updatedAppointment = updated
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: PUT reschedules an appointment; if the user
            // backgrounds or dismisses mid-flight the server may already have
            // accepted the update. Painting a "Cancelled" error tempts a re-tap
            // that overwrites the row a second time — annoying but worse, if a
            // SMS/email confirmation hook is wired server-side the customer
            // gets two reminders. Stay silent on cancellation.
            return
        } catch {
            let appError = AppError.from(error)
            errorMessage = Self.message(for: appError)
            AppLog.ui.error("Appt edit submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private static func parseDate(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        let iso2 = ISO8601DateFormatter()
        if let d = iso2.date(from: raw) { return d }
        let sql = DateFormatter()
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sql.timeZone = TimeZone(identifier: "UTC")
        sql.locale = Locale(identifier: "en_US_POSIX")
        return sql.date(from: raw)
    }

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

// MARK: - Appointment convenience extensions

private extension Appointment {
    var assignedId: Int64? { nil }  // assignedTo not in model yet — future

    var durationInterval: TimeInterval? {
        guard let s = startTime, let e = endTime else { return nil }
        // BUGHUNT-2026-05-18: was `ISO8601DateFormatter()` with default options,
        // which rejects Node Date.toISOString() millisecond strings. Both
        // start and end then fell through to sqlDate (which expects
        // "yyyy-MM-dd HH:mm:ss" — also a miss for ISO input), so this always
        // returned nil. The Edit screen then defaulted to a 60-minute slot
        // even when the existing appointment was 30/90/120 minutes — the
        // user had to re-pick the right duration on every edit. Try
        // fractional → plain → sql to match the parseDate chain above.
        guard let start = AppointmentDurationParser.parse(s),
              let end   = AppointmentDurationParser.parse(e) else { return nil }
        let diff = end.timeIntervalSince(start)
        return diff > 0 ? diff : nil
    }
}

private enum AppointmentDurationParser {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let sql: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        isoFractional.date(from: raw)
            ?? isoPlain.date(from: raw)
            ?? sql.date(from: raw)
    }
}
