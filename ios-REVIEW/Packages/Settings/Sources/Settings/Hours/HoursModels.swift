import Foundation

// MARK: - §19 Hours Models

/// Full weekly schedule for a tenant.
public struct BusinessHoursWeek: Codable, Sendable, Hashable {
    /// Always 7 entries, one per weekday (1 = Sunday … 7 = Saturday).
    public var days: [BusinessDay]

    public init(days: [BusinessDay]) {
        self.days = days
    }

    /// Returns the ``BusinessDay`` for the given weekday component (1-7).
    public func day(for weekday: Int) -> BusinessDay? {
        days.first { $0.weekday == weekday }
    }

    /// Returns a copy with the given day replaced.
    public func updatingDay(_ updated: BusinessDay) -> BusinessHoursWeek {
        var copy = self
        if let idx = copy.days.firstIndex(where: { $0.weekday == updated.weekday }) {
            copy.days[idx] = updated
        }
        return copy
    }

    /// Default open-all-weekdays schedule (Mon-Fri 9-17, Sat-Sun closed).
    public static var defaultWeek: BusinessHoursWeek {
        let days = (1...7).map { weekday -> BusinessDay in
            let isWeekday = weekday >= 2 && weekday <= 6 // Mon-Fri
            return BusinessDay(
                weekday: weekday,
                isOpen: isWeekday,
                openAt: isWeekday ? DateComponents(hour: 9, minute: 0) : nil,
                closeAt: isWeekday ? DateComponents(hour: 17, minute: 0) : nil,
                breaks: nil
            )
        }
        return BusinessHoursWeek(days: days)
    }
}

/// One day in the weekly schedule.
public struct BusinessDay: Codable, Sendable, Hashable {
    /// 1 = Sunday, 2 = Monday, …, 7 = Saturday (matches `Calendar.Component.weekday`).
    public var weekday: Int
    public var isOpen: Bool
    public var openAt: DateComponents?
    public var closeAt: DateComponents?
    /// Optional mid-day breaks (lunch, etc.).
    public var breaks: [TimeBreak]?

    public init(
        weekday: Int,
        isOpen: Bool,
        openAt: DateComponents? = nil,
        closeAt: DateComponents? = nil,
        breaks: [TimeBreak]? = nil
    ) {
        self.weekday = weekday
        self.isOpen = isOpen
        self.openAt = openAt
        self.closeAt = closeAt
        self.breaks = breaks
    }

    /// Localised display name (Sunday, Monday, …).
    public var displayName: String {
        let symbols = Calendar.current.weekdaySymbols
        let idx = (weekday - 1) % 7
        return symbols[idx]
    }

    /// Short display name (Sun, Mon, …).
    public var shortName: String {
        let symbols = Calendar.current.shortWeekdaySymbols
        let idx = (weekday - 1) % 7
        return symbols[idx]
    }
}

/// A single break window within a business day.
public struct TimeBreak: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var startAt: DateComponents
    public var endAt: DateComponents
    /// Optional human label, e.g. "Lunch".
    public var label: String?

    public init(id: UUID = UUID(), startAt: DateComponents, endAt: DateComponents, label: String? = nil) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
        self.label = label
    }
}

// MARK: - Holiday Exceptions

/// A single holiday / closure / special-hours exception.
public struct HolidayException: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var date: Date
    /// `false` = fully closed; `true` = open with custom hours.
    public var isOpen: Bool
    public var openAt: DateComponents?
    public var closeAt: DateComponents?
    /// Human-readable reason, e.g. "Christmas Day".
    public var reason: String
    public var recurring: Recurrence

    public init(
        id: String = UUID().uuidString,
        date: Date,
        isOpen: Bool,
        openAt: DateComponents? = nil,
        closeAt: DateComponents? = nil,
        reason: String,
        recurring: Recurrence = .once
    ) {
        self.id = id
        self.date = date
        self.isOpen = isOpen
        self.openAt = openAt
        self.closeAt = closeAt
        self.reason = reason
        self.recurring = recurring
    }
}

public enum Recurrence: String, Codable, Sendable, CaseIterable {
    case once, yearly, monthly, weekly

    public var displayName: String {
        switch self {
        case .once:    return "One-time"
        case .yearly:  return "Yearly"
        case .monthly: return "Monthly"
        case .weekly:  return "Weekly"
        }
    }
}
