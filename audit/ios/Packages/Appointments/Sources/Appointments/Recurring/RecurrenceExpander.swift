import Foundation

// MARK: - RecurrenceExpander

/// Pure helper — expands a `RecurrenceRule` into concrete `Date` occurrences.
/// No I/O, fully testable without mocks.
public enum RecurrenceExpander: Sendable {

    // MARK: - Constants

    /// Hard cap to prevent runaway expansion.
    private static let maxOccurrences = 1_000

    // MARK: - Public API

    /// Expands `rule` starting at `startDate` and returns all occurrences
    /// that fall within `[startDate, endDate]`.
    ///
    /// - Parameters:
    ///   - rule:      The recurrence rule to expand.
    ///   - startDate: The anchor date (first potential occurrence).
    ///   - endDate:   The inclusive upper bound of the window to return.
    /// - Returns: Sorted array of concrete occurrence dates.
    public static func expand(
        rule: RecurrenceRule,
        startDate: Date,
        endDate: Date
    ) -> [Date] {
        guard startDate <= endDate else { return [] }

        var results: [Date] = []
        var candidate = startDate
        var count = 0
        let cal = Calendar(identifier: .gregorian)

        // Precompute exception day set for fast lookup (day granularity in UTC).
        let exceptionDayStrings = Set(rule.exceptionDates.map { dayString($0, cal: cal) })

        while count < maxOccurrences {
            // Apply count / until caps.
            switch rule.endMode {
            case .count(let max) where results.count >= max:
                return results
            case .untilDate(let until) where candidate > until:
                return results
            default:
                break
            }

            if candidate > endDate { break }

            if isOccurrence(candidate: candidate, rule: rule, startDate: startDate, cal: cal) {
                let dayStr = dayString(candidate, cal: cal)
                if !exceptionDayStrings.contains(dayStr) {
                    results.append(candidate)
                }
            }

            // Advance by smallest unit of the frequency.
            guard let next = advance(from: candidate, rule: rule, cal: cal) else { break }
            candidate = next
            count += 1
        }

        return results
    }

    // MARK: - Private: date matching

    private static func isOccurrence(
        candidate: Date,
        rule: RecurrenceRule,
        startDate: Date,
        cal: Calendar
    ) -> Bool {
        switch rule.frequency {
        case .daily:
            return true

        case .weekly:
            let weekday = cal.component(.weekday, from: candidate) - 1 // 0=Sun
            if rule.weekdays.isEmpty {
                // No weekday restriction — match same weekday as startDate.
                let startWeekday = cal.component(.weekday, from: startDate) - 1
                return weekday == startWeekday
            }
            return rule.weekdays.contains(weekday)

        case .monthly:
            return isMonthlyOccurrence(candidate: candidate, rule: rule, startDate: startDate, cal: cal)

        case .yearly:
            let cComps = cal.dateComponents([.month, .day], from: candidate)
            let sComps = cal.dateComponents([.month, .day], from: startDate)
            return cComps.month == sComps.month && cComps.day == sComps.day
        }
    }

    private static func isMonthlyOccurrence(
        candidate: Date,
        rule: RecurrenceRule,
        startDate: Date,
        cal: Calendar
    ) -> Bool {
        switch rule.monthlyMode {
        case .onDayN:
            let candidateDay = cal.component(.day, from: candidate)
            let startDay = cal.component(.day, from: startDate)
            return candidateDay == startDay

        case .onNthWeekday:
            // "Nth weekday of month" — e.g. 3rd Tuesday.
            let (nth, weekday) = nthWeekdayOf(date: startDate, cal: cal)
            let (cNth, cWeekday) = nthWeekdayOf(date: candidate, cal: cal)
            return cNth == nth && cWeekday == weekday
        }
    }

    /// Returns (nth occurrence, weekday 1-7) of `date` within its month.
    private static func nthWeekdayOf(date: Date, cal: Calendar) -> (Int, Int) {
        let day = cal.component(.day, from: date)
        let weekday = cal.component(.weekday, from: date)
        let nth = (day - 1) / 7 + 1
        return (nth, weekday)
    }

    // MARK: - Private: advance

    /// Advances `from` by one step appropriate for the frequency.
    private static func advance(from date: Date, rule: RecurrenceRule, cal: Calendar) -> Date? {
        switch rule.frequency {
        case .daily:
            return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly:
            return cal.date(byAdding: .day, value: 1, to: date)
        case .monthly:
            // Advance day-by-day to correctly handle month-end edge cases.
            return cal.date(byAdding: .day, value: 1, to: date)
        case .yearly:
            return cal.date(byAdding: .day, value: 1, to: date)
        }
    }

    // MARK: - Private: helpers

    private static func dayString(_ date: Date, cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year!)-\(c.month!)-\(c.day!)"
    }
}
