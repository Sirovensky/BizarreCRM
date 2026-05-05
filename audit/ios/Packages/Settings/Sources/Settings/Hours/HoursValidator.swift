import Foundation

// MARK: - §19 HoursValidator

/// Pure helper used by `AppointmentCreate` to grey out unavailable time slots.
/// No I/O — safe to call on any thread.
public enum HoursValidator {

    /// Returns `true` when `slot` falls inside an open period (not a break,
    /// not a holiday closure).
    ///
    /// - Parameters:
    ///   - slot: The proposed appointment start time (UTC).
    ///   - hoursWeek: The tenant's weekly schedule.
    ///   - holidays: Any holiday / closure overrides.
    ///   - timezone: The tenant's local timezone. Defaults to `TimeZone.current`
    ///     but callers **must** pass the tenant TZ explicitly — never rely on
    ///     the device TZ.
    public static func isSlotValid(
        _ slot: Date,
        hoursWeek: BusinessHoursWeek,
        holidays: [HolidayException],
        timezone: TimeZone = .current
    ) -> Bool {
        let status = HoursCalculator.currentStatus(
            at: slot,
            week: hoursWeek,
            holidays: holidays,
            timezone: timezone
        )
        switch status {
        case .open:    return true
        case .closed, .onBreak: return false
        }
    }
}
