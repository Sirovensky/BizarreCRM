import Foundation

// MARK: - OvertimeBreakdown

/// Result of an overtime computation for a set of shifts in a pay period.
///
/// All values are in **minutes** (rational representation; no floating-point
/// hour fractions). Callers divide by 60.0 for display.
public struct OvertimeBreakdown: Sendable, Equatable {
    /// Regular minutes (≤ daily/weekly thresholds, not holiday-rated).
    public let regularMinutes: Int
    /// Weekly overtime minutes (beyond 40 hrs/week by default).
    public let overtimeMinutes: Int
    /// Daily double-time minutes (beyond 12 hrs/day in CA-style rules).
    public let doubleTimeMinutes: Int
    /// Holiday minutes (on designated holiday dates).
    public let holidayMinutes: Int
    /// `regularMinutes + overtimeMinutes + doubleTimeMinutes + holidayMinutes`
    public let totalMinutes: Int

    public init(
        regularMinutes: Int,
        overtimeMinutes: Int,
        doubleTimeMinutes: Int,
        holidayMinutes: Int,
        totalMinutes: Int
    ) {
        self.regularMinutes = regularMinutes
        self.overtimeMinutes = overtimeMinutes
        self.doubleTimeMinutes = doubleTimeMinutes
        self.holidayMinutes = holidayMinutes
        self.totalMinutes = totalMinutes
    }
}

// MARK: - OvertimeCalculator

/// Pure, stateless overtime engine.
///
/// - All input time values are in **minutes**.
/// - No mutation; returns a new `OvertimeBreakdown` each call.
/// - Server is authoritative for payroll; this is display-only.
/// - Week boundary: ISO week (Mon–Sun) in UTC, matching the server convention.
public enum OvertimeCalculator {

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    // MARK: - Public

    /// Compute overtime breakdown for one pay period.
    ///
    /// Algorithm:
    /// 1. Deduct unpaid breaks from each shift's raw duration.
    /// 2. Group shifts by calendar day.
    /// 3. For each day: compute daily regular/OT/double-time.
    /// 4. Accumulate weekly totals; apply weekly OT threshold after daily.
    /// 5. Flag holiday minutes.
    ///
    /// Spans midnight: a shift whose clock-in and clock-out are on different
    /// calendar days is split at midnight and counted toward each day.
    public static func compute(
        shifts: [Shift],
        breaks: [BreakEntry],
        rules: OvertimeRules
    ) -> OvertimeBreakdown {
        // Build a lookup: shiftId → unpaid break minutes
        let unpaidBreakMinutes = buildUnpaidBreakMap(breaks: breaks)

        // Effective minutes per shift after deducting unpaid breaks
        let shiftDurations: [(shift: Shift, effectiveMinutes: Int)] = shifts.compactMap { shift in
            guard let raw = shift.rawDurationMinutes else { return nil }
            let deduct = unpaidBreakMinutes[shift.id] ?? 0
            let effective = max(0, raw - deduct)
            return (shift, effective)
        }

        // Split multi-day shifts and group by ISO date key (yyyy-MM-dd UTC)
        var dayBuckets: [String: (minutes: Int, isHoliday: Bool)] = [:]
        for (shift, effectiveMinutes) in shiftDurations {
            let segments = splitAcrossMidnight(shift: shift, effectiveMinutes: effectiveMinutes)
            for (dayKey, segMinutes, isHoliday) in segments {
                let existing = dayBuckets[dayKey] ?? (0, false)
                dayBuckets[dayKey] = (existing.minutes + segMinutes, isHoliday || existing.isHoliday)
            }
        }

        // Accumulate weekly OT; process days in chronological order
        let sortedDays = dayBuckets.keys.sorted()

        var weeklyAccumulatorMinutes = 0
        var currentWeekKey: String? = nil

        var regular = 0
        var overtime = 0
        var doubleTime = 0
        var holiday = 0

        for dayKey in sortedDays {
            guard let (dayMinutes, isHoliday) = dayBuckets[dayKey] else { continue }
            let weekKey = isoWeekKey(for: dayKey)
            if weekKey != currentWeekKey {
                currentWeekKey = weekKey
                weeklyAccumulatorMinutes = 0
            }

            if isHoliday && rules.holidayMultiplier > 1.0 {
                // Count all holiday hours as holiday; still apply daily checks
                holiday += dayMinutes
                // Still count toward weekly hours for weekly OT
                weeklyAccumulatorMinutes += dayMinutes
                continue
            }

            let (dayRegular, dayOT, dayDouble) = applyDailyRules(
                minutes: dayMinutes,
                rules: rules
            )

            // Now apply weekly OT to the daily-regular bucket
            let (wkRegular, wkOT) = applyWeeklyOT(
                newRegularMinutes: dayRegular,
                accumulated: weeklyAccumulatorMinutes,
                rules: rules
            )

            regular += wkRegular
            overtime += wkOT + dayOT
            doubleTime += dayDouble
            weeklyAccumulatorMinutes += dayMinutes
        }

        let total = regular + overtime + doubleTime + holiday
        return OvertimeBreakdown(
            regularMinutes: regular,
            overtimeMinutes: overtime,
            doubleTimeMinutes: doubleTime,
            holidayMinutes: holiday,
            totalMinutes: total
        )
    }

    // MARK: - Private helpers

    /// Returns a map from shiftId → total unpaid break minutes for that shift.
    private static func buildUnpaidBreakMap(breaks: [BreakEntry]) -> [Int64: Int] {
        var map: [Int64: Int] = [:]
        for entry in breaks where !entry.paid {
            guard let dur = entry.duration else { continue }
            map[entry.shiftId, default: 0] += dur
        }
        return map
    }

    /// Splits a shift's effective minutes across calendar days (UTC midnight).
    ///
    /// Returns an array of `(dayKey, minutes, isHoliday)`.
    private static func splitAcrossMidnight(
        shift: Shift,
        effectiveMinutes: Int
    ) -> [(dayKey: String, minutes: Int, isHoliday: Bool)] {
        guard let inDate = ISO8601DateFormatter().date(from: shift.clockIn),
              let outDate = shift.clockOut.flatMap({ ISO8601DateFormatter().date(from: $0) }),
              outDate > inDate
        else {
            // Fallback: put all minutes on the clock-in day
            let dayKey = dayKeyFromISO(shift.clockIn)
            return [(dayKey ?? "unknown", effectiveMinutes, shift.isHoliday)]
        }

        // Walk through each calendar day boundary between inDate and outDate
        var segments: [(String, Int, Bool)] = []
        var cursor = inDate
        let totalSeconds = outDate.timeIntervalSince(inDate)
        let scale = totalSeconds > 0 ? Double(effectiveMinutes) / (totalSeconds / 60.0) : 1.0

        while cursor < outDate {
            let startOfNextDay = utcCalendar.date(byAdding: .day, value: 1,
                                                   to: utcCalendar.startOfDay(for: cursor))!
            let segEnd = min(startOfNextDay, outDate)
            let rawSeg = segEnd.timeIntervalSince(cursor) / 60.0
            let scaledSeg = max(0, Int((rawSeg * scale).rounded()))
            let dk = isoDateKey(for: cursor)
            segments.append((dk, scaledSeg, shift.isHoliday))
            cursor = startOfNextDay
        }
        return segments
    }

    /// Apply daily OT/double-time rules to a single day's minutes.
    private static func applyDailyRules(
        minutes: Int,
        rules: OvertimeRules
    ) -> (regular: Int, overtime: Int, doubleTime: Int) {
        // Daily double-time threshold (CA 12h = 720 min)
        if rules.dailyDoubleTimeThresholdMinutes > 0, minutes > rules.dailyDoubleTimeThresholdMinutes {
            let double = minutes - rules.dailyDoubleTimeThresholdMinutes
            let aboveRegular = rules.dailyDoubleTimeThresholdMinutes - rules.dailyOvertimeThresholdMinutes
            let ot = max(0, aboveRegular)
            let reg = min(minutes, rules.dailyOvertimeThresholdMinutes > 0
                          ? rules.dailyOvertimeThresholdMinutes
                          : rules.dailyDoubleTimeThresholdMinutes)
            return (reg, ot, double)
        }
        // Daily OT threshold (CA 8h = 480 min)
        if rules.dailyOvertimeThresholdMinutes > 0, minutes > rules.dailyOvertimeThresholdMinutes {
            let ot = minutes - rules.dailyOvertimeThresholdMinutes
            return (rules.dailyOvertimeThresholdMinutes, ot, 0)
        }
        // No daily OT (federal)
        return (minutes, 0, 0)
    }

    /// Redistribute daily-regular minutes into weekly regular/OT buckets.
    private static func applyWeeklyOT(
        newRegularMinutes: Int,
        accumulated: Int,
        rules: OvertimeRules
    ) -> (regular: Int, overtime: Int) {
        let threshold = rules.weeklyOvertimeThresholdMinutes
        guard threshold > 0 else { return (newRegularMinutes, 0) }

        let remainingCapacity = max(0, threshold - accumulated)
        if newRegularMinutes <= remainingCapacity {
            return (newRegularMinutes, 0)
        }
        let wkRegular = remainingCapacity
        let wkOT = newRegularMinutes - remainingCapacity
        return (wkRegular, wkOT)
    }

    // MARK: - Date helpers

    private static func dayKeyFromISO(_ iso: String) -> String? {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        return isoDateKey(for: d)
    }

    private static func isoDateKey(for date: Date) -> String {
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Returns a week key like "2026-W16" for grouping by ISO week.
    private static func isoWeekKey(for dayKey: String) -> String {
        guard let d = dateFromDayKey(dayKey) else { return dayKey }
        let comps = utcCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        let y = comps.yearForWeekOfYear ?? 1970
        let w = comps.weekOfYear ?? 1
        return String(format: "%04d-W%02d", y, w)
    }

    private static func dateFromDayKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d
        return utcCalendar.date(from: comps)
    }
}
