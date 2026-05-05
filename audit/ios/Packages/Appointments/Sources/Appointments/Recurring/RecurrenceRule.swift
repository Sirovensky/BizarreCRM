import Foundation

// MARK: - RecurrenceFrequency
// Canonical declaration — moved from Create/AppointmentRepeatRuleSheet.swift.
// Adds `yearly` and `Codable` conformance for deep recurrence.

public enum RecurrenceFrequency: String, CaseIterable, Sendable, Codable {
    case daily   = "Daily"
    case weekly  = "Weekly"
    case monthly = "Monthly"
    case yearly  = "Yearly"
}

// MARK: - MonthlyMode

public enum MonthlyMode: String, CaseIterable, Sendable, Codable {
    /// e.g. "on the 15th of the month"
    case onDayN       = "on_day_n"
    /// e.g. "on the 3rd Tuesday of the month"
    case onNthWeekday = "on_nth_weekday"

    public var displayName: String {
        switch self {
        case .onDayN:       return "On day N"
        case .onNthWeekday: return "On Nth weekday"
        }
    }
}

// MARK: - RecurrenceEndMode

public enum RecurrenceEndMode: Sendable {
    /// Repeat until a specific date (inclusive).
    case untilDate(Date)
    /// Repeat N times total.
    case count(Int)
    /// No end.
    case forever
}

extension RecurrenceEndMode: Equatable {
    public static func == (lhs: RecurrenceEndMode, rhs: RecurrenceEndMode) -> Bool {
        switch (lhs, rhs) {
        case (.untilDate(let a), .untilDate(let b)): return a == b
        case (.count(let a),     .count(let b)):     return a == b
        case (.forever,          .forever):          return true
        default:                                     return false
        }
    }
}

// MARK: - RecurrenceRule

/// Full-fidelity recurrence rule used throughout §10.6.
/// Replaces the simpler `RepeatRule` from Phase 3-4 where deep recurrence is needed.
/// `RepeatRule` is kept for backward compat in the create flow.
public struct RecurrenceRule: Sendable, Equatable {
    public var frequency: RecurrenceFrequency
    /// 0=Sun … 6=Sat; used for `.weekly`. Multi-select.
    public var weekdays: Set<Int>
    /// Monthly mode. Only meaningful when `frequency == .monthly`.
    public var monthlyMode: MonthlyMode
    /// How to end the series.
    public var endMode: RecurrenceEndMode
    /// Dates to skip (exception dates).
    public var exceptionDates: [Date]

    public init(
        frequency: RecurrenceFrequency = .weekly,
        weekdays: Set<Int> = [],
        monthlyMode: MonthlyMode = .onDayN,
        endMode: RecurrenceEndMode = .untilDate(
            Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        ),
        exceptionDates: [Date] = []
    ) {
        self.frequency = frequency
        self.weekdays = weekdays
        self.monthlyMode = monthlyMode
        self.endMode = endMode
        self.exceptionDates = exceptionDates
    }
}
