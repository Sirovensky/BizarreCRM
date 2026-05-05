import Foundation
import Networking

// MARK: - RecurrenceConflictReport

public struct RecurrenceConflictReport: Sendable {
    /// Dates that have at least one conflict.
    public let conflictingDates: [Date]
    /// Dates that are free.
    public let freeDates: [Date]

    public var hasConflicts: Bool { !conflictingDates.isEmpty }
}

// MARK: - RecurrenceConflictResolver

/// Pure helper — checks all instances of a recurring appointment against existing
/// appointments before they are created.
public enum RecurrenceConflictResolver: Sendable {

    /// Expands `rule` from `startDate` to `endDate`, then checks each instance
    /// (using `duration` as the appointment length) against `existingAppointments`.
    ///
    /// - Parameters:
    ///   - rule:                  The recurrence rule to expand.
    ///   - startDate:             Anchor / first occurrence.
    ///   - endDate:               Inclusive bound for expansion window.
    ///   - duration:              Appointment duration in seconds.
    ///   - existingAppointments:  Currently booked appointments.
    /// - Returns: A `RecurrenceConflictReport` with split free/conflicting dates.
    public static func check(
        rule: RecurrenceRule,
        startDate: Date,
        endDate: Date,
        duration: TimeInterval,
        existingAppointments: [Appointment]
    ) -> RecurrenceConflictReport {
        let dates = RecurrenceExpander.expand(rule: rule, startDate: startDate, endDate: endDate)

        var free: [Date] = []
        var conflicting: [Date] = []

        for date in dates {
            let interval = DateInterval(start: date, duration: duration)
            let conflicts = AppointmentConflictResolver.hasConflict(
                proposed: interval,
                existingAppointments: existingAppointments
            )
            if conflicts {
                conflicting.append(date)
            } else {
                free.append(date)
            }
        }

        return RecurrenceConflictReport(conflictingDates: conflicting, freeDates: free)
    }
}
