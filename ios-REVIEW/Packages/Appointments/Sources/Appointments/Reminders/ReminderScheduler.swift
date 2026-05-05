import Foundation

// MARK: - ReminderScheduler

/// Pure helper — computes when to send the appointment reminder.
/// If the naive send-time falls inside a quiet window it is pushed forward
/// to the quiet window's end (or returns nil if it would land after the appointment).
///
/// No I/O, fully testable without mocks.
public enum ReminderScheduler: Sendable {

    // MARK: - Public API

    /// Computes the time at which the reminder should be sent.
    ///
    /// - Parameters:
    ///   - appointmentAt:  The date/time of the appointment.
    ///   - offsetHours:    How many hours before the appointment to remind.
    ///   - quietHours:     Optional quiet window. When non-nil, any send-time
    ///                     that falls inside the window is shifted to the window end.
    /// - Returns: The send time, or `nil` if it would be in the past or after
    ///            the appointment after adjustment.
    public static func computeSendTime(
        appointmentAt: Date,
        offsetHours: Int,
        quietHours: QuietHoursWindow?
    ) -> Date? {
        guard offsetHours >= 0 else { return nil }

        let naive = appointmentAt.addingTimeInterval(-Double(offsetHours) * 3600)

        // If naive time is already past, no point sending.
        guard naive > Date.distantPast else { return nil }

        guard let quiet = quietHours else {
            return naive < appointmentAt ? naive : nil
        }

        let adjusted = shiftOutOfQuietWindow(date: naive, quiet: quiet)

        // If adjusted falls at or after the appointment, we can't send.
        guard adjusted < appointmentAt else { return nil }
        return adjusted
    }

    // MARK: - Private

    /// Returns `date` unchanged if it's outside the quiet window,
    /// or the quiet-window end time on the same (or next) calendar day otherwise.
    private static func shiftOutOfQuietWindow(
        date: Date,
        quiet: QuietHoursWindow
    ) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let hour = cal.component(.hour, from: date)

        guard isInQuietWindow(hour: hour, quiet: quiet) else { return date }

        // Push to quiet-window end on the same day.
        // If end < start (overnight), end refers to next calendar day.
        let endHour = quiet.endHour
        let isOvernight = quiet.startHour > quiet.endHour

        if isOvernight && hour >= quiet.startHour {
            // In the overnight start portion → end is next morning.
            if let nextDay = cal.date(byAdding: .day, value: 1, to: date),
               let shifted = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: nextDay) {
                return shifted
            }
        }

        if let shifted = cal.date(bySettingHour: endHour, minute: 0, second: 0, of: date) {
            return shifted
        }
        return date
    }

    /// Returns `true` if `hour` falls within the quiet window.
    private static func isInQuietWindow(hour: Int, quiet: QuietHoursWindow) -> Bool {
        let s = quiet.startHour
        let e = quiet.endHour
        guard s != e else { return false }
        if s < e {
            return hour >= s && hour < e
        } else {
            // Overnight
            return hour >= s || hour < e
        }
    }
}
