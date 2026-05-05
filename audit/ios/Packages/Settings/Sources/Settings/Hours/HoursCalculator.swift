import Foundation

// MARK: - §19 HoursCalculator

/// The result of asking "is the business open right now?"
public enum OpenStatus: Sendable, Equatable {
    /// Shop is open. Closes at the given Date (in the tenant timezone).
    case open(closesAt: Date)
    /// Shop is closed. Opens at the given Date if determinable.
    case closed(opensAt: Date?)
    /// Currently in a mid-day break.
    case onBreak(endsAt: Date)
}

/// Pure stateless calculator — no I/O. All functions are `static` so they
/// are trivially testable without any setup.
public enum HoursCalculator {

    // MARK: - Public API

    /// Computes the current open/closed/break status at `date`.
    ///
    /// Priority:
    /// 1. Holiday exception that matches today (supports `once`, `yearly`,
    ///    `monthly`, `weekly` recurrences).
    /// 2. Regular weekly schedule.
    /// 3. If open, check whether a break is active → `.onBreak`.
    public static func currentStatus(
        at date: Date,
        week: BusinessHoursWeek,
        holidays: [HolidayException],
        timezone: TimeZone
    ) -> OpenStatus {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone

        // 1. Resolve holiday override.
        if let holiday = resolveHoliday(at: date, holidays: holidays, calendar: cal) {
            return statusFromHoliday(holiday, at: date, calendar: cal)
        }

        // 2. Regular schedule.
        let weekday = cal.component(.weekday, from: date) // 1-7
        guard let day = week.day(for: weekday), day.isOpen,
              let openDC = day.openAt, let closeDC = day.closeAt else {
            // Closed today — find next open moment.
            let nextOpen = nextOpenDate(after: date, week: week, holidays: holidays, calendar: cal)
            return .closed(opensAt: nextOpen)
        }

        guard let openDate = absoluteDate(from: openDC, on: date, calendar: cal),
              let closeDate = spanMidnightAware(open: openDC, close: closeDC, on: date, calendar: cal)
        else {
            return .closed(opensAt: nil)
        }

        guard date >= openDate && date < closeDate else {
            if date < openDate {
                return .closed(opensAt: openDate)
            }
            // After close — find next open.
            let nextOpen = nextOpenDate(after: date, week: week, holidays: holidays, calendar: cal)
            return .closed(opensAt: nextOpen)
        }

        // 3. Break check.
        if let br = activeBreak(at: date, breaks: day.breaks, on: date, calendar: cal) {
            let endDate = absoluteDate(from: br.endAt, on: date, calendar: cal) ?? date
            return .onBreak(endsAt: endDate)
        }

        return .open(closesAt: closeDate)
    }

    // MARK: - Holiday resolution

    /// Returns the first holiday that applies to `date` for any recurrence.
    static func resolveHoliday(
        at date: Date,
        holidays: [HolidayException],
        calendar: Calendar
    ) -> HolidayException? {
        let dateComps = calendar.dateComponents([.year, .month, .day, .weekday, .weekOfMonth], from: date)
        return holidays.first { holiday in
            matchesRecurrence(holiday: holiday, dateComps: dateComps, calendar: calendar)
        }
    }

    /// Checks whether a holiday's recurrence rule fires on the given date components.
    static func matchesRecurrence(
        holiday: HolidayException,
        dateComps: DateComponents,
        calendar: Calendar
    ) -> Bool {
        let holidayComps = calendar.dateComponents([.year, .month, .day, .weekday], from: holiday.date)

        switch holiday.recurring {
        case .once:
            return holidayComps.year == dateComps.year
                && holidayComps.month == dateComps.month
                && holidayComps.day == dateComps.day

        case .yearly:
            return holidayComps.month == dateComps.month
                && holidayComps.day == dateComps.day

        case .monthly:
            return holidayComps.day == dateComps.day

        case .weekly:
            return holidayComps.weekday == dateComps.weekday
        }
    }

    // MARK: - Status from holiday

    static func statusFromHoliday(
        _ holiday: HolidayException,
        at date: Date,
        calendar: Calendar
    ) -> OpenStatus {
        guard holiday.isOpen,
              let openDC = holiday.openAt,
              let closeDC = holiday.closeAt,
              let openDate = absoluteDate(from: openDC, on: date, calendar: calendar),
              let closeDate = spanMidnightAware(open: openDC, close: closeDC, on: date, calendar: calendar)
        else {
            return .closed(opensAt: nil)
        }

        if date >= openDate && date < closeDate {
            return .open(closesAt: closeDate)
        } else if date < openDate {
            return .closed(opensAt: openDate)
        }
        return .closed(opensAt: nil)
    }

    // MARK: - Next open computation

    /// Searches forward (up to 8 days) for the next open moment.
    static func nextOpenDate(
        after date: Date,
        week: BusinessHoursWeek,
        holidays: [HolidayException],
        calendar: Calendar
    ) -> Date? {
        for offset in 1...8 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            let weekday = calendar.component(.weekday, from: candidate)

            // Check if holiday overrides this day.
            let holidayComps = calendar.dateComponents([.year, .month, .day, .weekday], from: candidate)
            if let holiday = holidays.first(where: { h in matchesRecurrence(holiday: h, dateComps: holidayComps, calendar: calendar) }) {
                if holiday.isOpen, let openDC = holiday.openAt,
                   let openDate = absoluteDate(from: openDC, on: candidate, calendar: calendar) {
                    return openDate
                }
                continue
            }

            // Regular schedule.
            guard let day = week.day(for: weekday), day.isOpen, let openDC = day.openAt else { continue }
            return absoluteDate(from: openDC, on: candidate, calendar: calendar)
        }
        return nil
    }

    // MARK: - Helpers

    /// Materialises `DateComponents` (hour+minute) onto `referenceDate`'s calendar day.
    static func absoluteDate(
        from components: DateComponents,
        on referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        var dc = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        dc.hour = components.hour ?? 0
        dc.minute = components.minute ?? 0
        dc.second = 0
        return calendar.date(from: dc)
    }

    /// Handles close times that cross midnight (e.g. 23:00 open, 02:00 close).
    static func spanMidnightAware(
        open: DateComponents,
        close: DateComponents,
        on referenceDate: Date,
        calendar: Calendar
    ) -> Date? {
        guard var closeDate = absoluteDate(from: close, on: referenceDate, calendar: calendar),
              let openDate = absoluteDate(from: open, on: referenceDate, calendar: calendar) else {
            return nil
        }
        // If close is before or equal to open, it spans midnight — add a day.
        if closeDate <= openDate {
            closeDate = calendar.date(byAdding: .day, value: 1, to: closeDate) ?? closeDate
        }
        return closeDate
    }

    /// Returns the active break (if any) at `date`.
    static func activeBreak(
        at date: Date,
        breaks: [TimeBreak]?,
        on referenceDate: Date,
        calendar: Calendar
    ) -> TimeBreak? {
        guard let breaks else { return nil }
        return breaks.first { br in
            guard let startDate = absoluteDate(from: br.startAt, on: referenceDate, calendar: calendar),
                  let endDate = absoluteDate(from: br.endAt, on: referenceDate, calendar: calendar) else {
                return false
            }
            return date >= startDate && date < endDate
        }
    }
}
