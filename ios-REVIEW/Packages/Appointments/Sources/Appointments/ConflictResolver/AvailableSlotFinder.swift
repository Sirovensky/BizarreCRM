import Foundation

// MARK: - AvailableSlotFinder

/// Pure helper — finds free appointment slots on a given day.
/// No I/O, fully testable without mocks.
public enum AvailableSlotFinder: Sendable {

    // MARK: - Public API

    /// Returns all free `DateInterval`s on `date` where an appointment
    /// of `duration` could be scheduled, given `hours` and `busy` intervals.
    ///
    /// - Parameters:
    ///   - date:     The calendar day to search.
    ///   - duration: Required appointment length in seconds.
    ///   - hours:    The tenant's weekly business-hours schedule.
    ///   - busy:     Already-booked intervals (may span multiple days; only same-day portions matter).
    /// - Returns: Available `DateInterval`s sorted chronologically.
    public static func findSlots(
        on date: Date,
        duration: TimeInterval,
        hours: BusinessHoursWeek,
        busy: [DateInterval]
    ) -> [DateInterval] {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: date) // 1=Sun…7=Sat

        guard
            let day = hours.day(for: weekday),
            day.isOpen,
            let openComps  = day.openAt,
            let closeComps = day.closeAt,
            let open  = cal.date(bySettingHour: openComps.hour ?? 9,
                                 minute: openComps.minute ?? 0,
                                 second: 0, of: date),
            let close = cal.date(bySettingHour: closeComps.hour ?? 17,
                                 minute: closeComps.minute ?? 0,
                                 second: 0, of: date),
            open < close,
            duration > 0
        else { return [] }

        // Compute blocked intervals within the business day.
        let breaks = day.breaks ?? []
        var blocked: [DateInterval] = breaks.compactMap { br in
            guard
                let s = cal.date(bySettingHour: br.startAt.hour ?? 0,
                                 minute: br.startAt.minute ?? 0,
                                 second: 0, of: date),
                let e = cal.date(bySettingHour: br.endAt.hour ?? 0,
                                 minute: br.endAt.minute ?? 0,
                                 second: 0, of: date)
            else { return nil }
            return DateInterval(start: s, end: e)
        }

        // Clip busy intervals to the business day window.
        let busyClipped = busy.compactMap { interval -> DateInterval? in
            guard interval.start < close, interval.end > open else { return nil }
            let s = max(interval.start, open)
            let e = min(interval.end, close)
            guard s < e else { return nil }
            return DateInterval(start: s, end: e)
        }
        blocked.append(contentsOf: busyClipped)

        // Merge and sort blocked intervals.
        let merged = merge(intervals: blocked.sorted { $0.start < $1.start })

        // Walk free gaps and collect those ≥ duration.
        var slots: [DateInterval] = []
        var cursor = open

        for block in merged {
            if block.start > cursor {
                let free = DateInterval(start: cursor, end: block.start)
                if free.duration >= duration {
                    slots.append(contentsOf: chopIntoSlots(free, stepSize: duration))
                }
            }
            cursor = max(cursor, block.end)
        }

        // Trailing gap.
        if cursor < close {
            let free = DateInterval(start: cursor, end: close)
            if free.duration >= duration {
                slots.append(contentsOf: chopIntoSlots(free, stepSize: duration))
            }
        }

        return slots
    }

    // MARK: - Private

    /// Merges overlapping/adjacent sorted intervals.
    private static func merge(intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }
        var result = [intervals[0]]
        for next in intervals.dropFirst() {
            let last = result[result.count - 1]
            if next.start <= last.end {
                let merged = DateInterval(start: last.start, end: max(last.end, next.end))
                result[result.count - 1] = merged
            } else {
                result.append(next)
            }
        }
        return result
    }

    /// Chops a free window into back-to-back slots of exactly `stepSize`.
    private static func chopIntoSlots(_ window: DateInterval, stepSize: TimeInterval) -> [DateInterval] {
        var slots: [DateInterval] = []
        var t = window.start
        while t.addingTimeInterval(stepSize) <= window.end {
            slots.append(DateInterval(start: t, duration: stepSize))
            t = t.addingTimeInterval(stepSize)
        }
        return slots
    }
}

// MARK: - BusinessHoursWeek (local types)
// The Settings package owns the canonical BusinessHoursWeek / BusinessDay / TimeBreak.
// Appointments deliberately does not depend on Settings to keep the DAG acyclic.
// These local value types mirror the Settings shapes for AvailableSlotFinder only.

public struct BusinessHoursWeek: Sendable {
    public var days: [BusinessDay]
    public init(days: [BusinessDay]) { self.days = days }
    public func day(for weekday: Int) -> BusinessDay? {
        days.first { $0.weekday == weekday }
    }
    public static var defaultWeek: BusinessHoursWeek {
        let days = (1...7).map { w -> BusinessDay in
            let open = w >= 2 && w <= 6
            return BusinessDay(
                weekday: w, isOpen: open,
                openAt: open ? DateComponents(hour: 9, minute: 0) : nil,
                closeAt: open ? DateComponents(hour: 17, minute: 0) : nil,
                breaks: nil
            )
        }
        return BusinessHoursWeek(days: days)
    }
}

public struct BusinessDay: Sendable {
    public var weekday: Int
    public var isOpen: Bool
    public var openAt: DateComponents?
    public var closeAt: DateComponents?
    public var breaks: [BusinessBreak]?
    public init(
        weekday: Int, isOpen: Bool,
        openAt: DateComponents? = nil,
        closeAt: DateComponents? = nil,
        breaks: [BusinessBreak]? = nil
    ) {
        self.weekday = weekday; self.isOpen = isOpen
        self.openAt = openAt; self.closeAt = closeAt; self.breaks = breaks
    }
}

/// A break window within a business day (mirrors Settings.TimeBreak).
public struct BusinessBreak: Sendable {
    public var startAt: DateComponents
    public var endAt: DateComponents
    public init(startAt: DateComponents, endAt: DateComponents) {
        self.startAt = startAt; self.endAt = endAt
    }
}
