import Foundation
import Core
import Networking
#if canImport(EventKit)
import EventKit
#endif

// MARK: - CalendarExportError

public enum CalendarExportError: Error, LocalizedError, Sendable {
    case notAuthorized
    case appointmentNotFound
    case missingStartTime
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:      return "Calendar access was not granted."
        case .appointmentNotFound: return "Appointment not found."
        case .missingStartTime:   return "Appointment is missing a start time."
        case .saveFailed(let msg): return "Failed to save event: \(msg)"
        }
    }
}

// MARK: - CalendarExportService

/// Actor — exports an appointment to the user's iOS Calendar via EventKit.
///
/// Requires `NSCalendarsFullAccessUsageDescription` in Info.plist (iOS 17+).
/// Add the key via `ios/scripts/write-info-plist.sh`.
public actor CalendarExportService {

    private let api: APIClient
    #if canImport(EventKit)
    private let store = EKEventStore()
    #endif

    public init(api: APIClient) { self.api = api }

    // MARK: - Public API

    /// Fetches the appointment and adds it to the user's default calendar.
    /// - Parameter appointmentId: Server-side ID.
    /// - Throws: `CalendarExportError` on failure.
    public func exportToCalendar(appointmentId: Int64) async throws {
        // 1. Ensure permission.
        let granted = await CalendarPermissionHelper.requestAccess()
        guard granted else { throw CalendarExportError.notAuthorized }

        // 2. Fetch appointment.
        let appointments = try await api.listAppointments()
        guard let appt = appointments.first(where: { $0.id == appointmentId }) else {
            throw CalendarExportError.appointmentNotFound
        }

        // 3. Parse dates.
        guard let startDate = parseDate(appt.startTime) else {
            throw CalendarExportError.missingStartTime
        }
        let endDate = parseDate(appt.endTime) ?? startDate.addingTimeInterval(3600)

        // 4. Create EKEvent.
        try await createEvent(appointment: appt, start: startDate, end: endDate)
    }

    // MARK: - Private

    private func createEvent(appointment: Appointment, start: Date, end: Date) async throws {
        #if canImport(EventKit) && !os(macOS)
        let event = EKEvent(eventStore: store)
        event.title = appointment.title ?? "Appointment"
        event.startDate = start
        event.endDate = end
        event.notes = appointment.notes
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
        } catch {
            throw CalendarExportError.saveFailed(error.localizedDescription)
        }
        #endif
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
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
}
