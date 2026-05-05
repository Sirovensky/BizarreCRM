import Foundation
import Networking

// MARK: - AppointmentConflictResolver

/// Pure helper: determines whether a proposed slot overlaps any existing appointment.
/// No I/O — fully testable without mocks.
public enum AppointmentConflictResolver: Sendable {

    /// Returns `true` if `proposed` overlaps any interval in `existing`.
    /// Touching boundaries (end == start) are NOT considered conflicts.
    public static func hasConflict(
        proposed: DateInterval,
        existingAppointments: [Appointment]
    ) -> Bool {
        let formatter = ISO8601DateFormatter()
        for appt in existingAppointments {
            guard
                let rawStart = appt.startTime,
                let rawEnd = appt.endTime,
                let s = parseDate(rawStart, formatter: formatter),
                let e = parseDate(rawEnd, formatter: formatter),
                s < e
            else { continue }

            let existing = DateInterval(start: s, end: e)
            if overlaps(proposed, existing) { return true }
        }
        return false
    }

    /// Returns filtered list of slots that do NOT conflict with existing appointments.
    public static func filterConflicting(
        slots: [AvailabilitySlot],
        duration: TimeInterval,
        existingAppointments: [Appointment]
    ) -> (free: [AvailabilitySlot], conflicting: [AvailabilitySlot]) {
        let formatter = ISO8601DateFormatter()
        var free: [AvailabilitySlot] = []
        var conflicting: [AvailabilitySlot] = []

        for slot in slots {
            guard let start = parseDate(slot.start, formatter: formatter) else {
                free.append(slot)
                continue
            }
            let end = start.addingTimeInterval(duration)
            let interval = DateInterval(start: start, end: end)
            if hasConflict(proposed: interval, existingAppointments: existingAppointments) {
                conflicting.append(slot)
            } else {
                free.append(slot)
            }
        }
        return (free, conflicting)
    }

    // MARK: - Private

    private static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        // Overlaps if one starts before the other ends AND ends after the other starts
        a.start < b.end && a.end > b.start
    }

    private static func parseDate(_ raw: String, formatter: ISO8601DateFormatter) -> Date? {
        // Try ISO-8601 first, then fallback "YYYY-MM-DD HH:MM:SS"
        if let d = formatter.date(from: raw) { return d }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        return fallback.date(from: raw)
    }
}
