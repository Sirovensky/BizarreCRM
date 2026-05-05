import XCTest
@testable import Timeclock

/// Tests for `OvertimeCalculator` — §14.2.
///
/// Coverage targets:
///  - Federal rules (40 hr/wk OT only)
///  - California daily OT (8 hr) + double-time (12 hr) + weekly OT
///  - Holiday rules
///  - Unpaid break deduction
///  - Spans-midnight shift splitting
///  - Week boundary (Mon/Sun transition)
///  - Edge cases: zero shifts, open shifts, bad ISO strings
final class OvertimeCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private func shift(
        id: Int64 = 1,
        employeeId: Int64 = 1,
        clockIn: String,
        clockOut: String? = nil,
        totalMinutes: Int? = nil,
        isHoliday: Bool = false
    ) -> Shift {
        Shift(id: id, employeeId: employeeId, clockIn: clockIn, clockOut: clockOut,
              totalMinutes: totalMinutes, isHoliday: isHoliday)
    }

    private func breakEntry(
        id: Int64 = 1,
        shiftId: Int64 = 1,
        startAt: String,
        endAt: String,
        paid: Bool = false
    ) -> BreakEntry {
        BreakEntry(id: id, employeeId: 1, shiftId: shiftId, startAt: startAt, endAt: endAt,
                   kind: .rest, paid: paid)
    }

    /// Build ISO-8601 UTC string for a specific date+time.
    private func iso(year: Int = 2026, month: Int = 4, day: Int, hour: Int, minute: Int = 0) -> String {
        String(format: "%04d-%02d-%02dT%02d:%02d:00Z", year, month, day, hour, minute)
    }

    // MARK: - Federal rules

    func test_federal_noOT_singleDay_8hrs() {
        // 8-hour shift, federal rules → all regular
        let s = shift(clockIn: iso(day: 20, hour: 9), clockOut: iso(day: 20, hour: 17))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .federal)
        XCTAssertEqual(result.regularMinutes, 480)
        XCTAssertEqual(result.overtimeMinutes, 0)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
        XCTAssertEqual(result.holidayMinutes, 0)
        XCTAssertEqual(result.totalMinutes, 480)
    }

    func test_federal_weeklyOT_kicks_in_at_40hrs() {
        // Mon–Fri Apr 20–24, 9h each = 45h; first 40h regular, 5h (300min) OT
        var shifts: [Shift] = []
        for (idx, day) in [20, 21, 22, 23, 24].enumerated() {
            shifts.append(shift(id: Int64(idx + 1),
                                clockIn:  iso(day: day, hour: 9),
                                clockOut: iso(day: day, hour: 18)))  // 9h each
        }
        let result = OvertimeCalculator.compute(shifts: shifts, breaks: [], rules: .federal)
        // 5 × 540 = 2700 min total; 2400 regular, 300 OT
        XCTAssertEqual(result.totalMinutes, 2700)
        XCTAssertEqual(result.regularMinutes, 2400)
        XCTAssertEqual(result.overtimeMinutes, 300)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
    }

    func test_federal_under40hrs_noOT() {
        // 4 days × 8h = 32h → no OT
        var shifts: [Shift] = []
        for (idx, day) in [20, 21, 22, 23].enumerated() {
            shifts.append(shift(id: Int64(idx + 1),
                                clockIn:  iso(day: day, hour: 9),
                                clockOut: iso(day: day, hour: 17)))
        }
        let result = OvertimeCalculator.compute(shifts: shifts, breaks: [], rules: .federal)
        XCTAssertEqual(result.regularMinutes, 1920)
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    func test_federal_exactlyAt40hrs_noOT() {
        // 5 days × 8h = 40h → exactly at threshold, no OT
        var shifts: [Shift] = []
        for (idx, day) in [20, 21, 22, 23, 24].enumerated() {
            shifts.append(shift(id: Int64(idx + 1),
                                clockIn:  iso(day: day, hour: 9),
                                clockOut: iso(day: day, hour: 17)))
        }
        let result = OvertimeCalculator.compute(shifts: shifts, breaks: [], rules: .federal)
        XCTAssertEqual(result.regularMinutes, 2400)
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    // MARK: - California daily OT

    func test_california_dailyOT_9hrs() {
        // CA: 9h day → 8h regular + 1h OT
        let s = shift(clockIn: iso(day: 21, hour: 8), clockOut: iso(day: 21, hour: 17))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.regularMinutes, 480)
        XCTAssertEqual(result.overtimeMinutes, 60)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
        XCTAssertEqual(result.totalMinutes, 540)
    }

    func test_california_doubleTime_13hrs() {
        // CA: 13h day → 8h regular + 4h OT + 1h double-time
        let s = shift(clockIn: iso(day: 21, hour: 7), clockOut: iso(day: 21, hour: 20))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.regularMinutes, 480)   // 8h
        XCTAssertEqual(result.overtimeMinutes, 240)  // 4h (8→12)
        XCTAssertEqual(result.doubleTimeMinutes, 60) // 1h (12→13)
        XCTAssertEqual(result.totalMinutes, 780)
    }

    func test_california_weeklyOTAndDailyOT_combine() {
        // 5 × 9h = 45h total (2700 min).
        // CA daily: each day → 8h regular + 1h daily OT.
        // Weekly accumulator tracks full shift (9h), so by day 5 accumulated = 4×9h = 2160 min.
        // Remaining weekly cap = 2400-2160 = 240 min regular; day5 regular (480) → 240 regular + 240 weekly OT.
        // Total regular: 4×480 + 240 = 2160; weekly OT: 240; daily OT: 5×60=300; total OT=540.
        var shifts: [Shift] = []
        for (idx, day) in [20, 21, 22, 23, 24].enumerated() {
            shifts.append(shift(id: Int64(idx + 1),
                                clockIn:  iso(day: day, hour: 8),
                                clockOut: iso(day: day, hour: 17)))  // 9h
        }
        let result = OvertimeCalculator.compute(shifts: shifts, breaks: [], rules: .california)
        XCTAssertEqual(result.regularMinutes, 2160)
        XCTAssertEqual(result.overtimeMinutes, 540)  // 300 daily + 240 weekly
        XCTAssertEqual(result.doubleTimeMinutes, 0)
        XCTAssertEqual(result.totalMinutes, 2700)
    }

    // MARK: - Holiday rules

    func test_holiday_minutesCounted() {
        let rules = OvertimeRules(
            weeklyOvertimeThresholdMinutes: 2400,
            weeklyOvertimeMultiplier: 1.5,
            holidayMultiplier: 1.5,
            holidayMonthDays: [MonthDay(month: 12, day: 25)]
        )
        let s = shift(clockIn: iso(day: 22, hour: 9), clockOut: iso(day: 22, hour: 17), isHoliday: true)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: rules)
        XCTAssertEqual(result.holidayMinutes, 480)
        XCTAssertEqual(result.regularMinutes, 0)
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    func test_holiday_multiplierOff_treatedAsRegular() {
        // holidayMultiplier = 1.0 → holiday flag doesn't split out holiday minutes
        let s = shift(clockIn: iso(day: 22, hour: 9), clockOut: iso(day: 22, hour: 17), isHoliday: true)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .federal)
        // federal has holidayMultiplier = 1.0 → treated as regular
        XCTAssertEqual(result.holidayMinutes, 0)
        XCTAssertEqual(result.regularMinutes, 480)
    }

    // MARK: - Break deductions

    func test_unpaidBreak_deductedFromShiftDuration() {
        // 9h shift, 30-min unpaid meal break → effective 8h 30min = 510 min
        let s = shift(clockIn: iso(day: 22, hour: 8), clockOut: iso(day: 22, hour: 17))
        let b = breakEntry(
            shiftId: 1,
            startAt: iso(day: 22, hour: 12),
            endAt:   iso(day: 22, hour: 12, minute: 30),
            paid: false
        )
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [b], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 510)
    }

    func test_paidBreak_notDeducted() {
        // 9h shift, 30-min paid break → effective 9h = 540 min (no deduct)
        let s = shift(clockIn: iso(day: 22, hour: 8), clockOut: iso(day: 22, hour: 17))
        let b = breakEntry(
            shiftId: 1,
            startAt: iso(day: 22, hour: 12),
            endAt:   iso(day: 22, hour: 12, minute: 30),
            paid: true
        )
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [b], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 540)
    }

    func test_multipleUnpaidBreaks_allDeducted() {
        // 10h shift; 30-min meal + 15-min rest = 45-min deduction → 555 min
        let s = shift(clockIn: iso(day: 22, hour: 7), clockOut: iso(day: 22, hour: 17))
        let b1 = breakEntry(id: 1, shiftId: 1,
                            startAt: iso(day: 22, hour: 10),
                            endAt:   iso(day: 22, hour: 10, minute: 15), paid: false)
        let b2 = breakEntry(id: 2, shiftId: 1,
                            startAt: iso(day: 22, hour: 12),
                            endAt:   iso(day: 22, hour: 12, minute: 30), paid: false)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [b1, b2], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 555)
    }

    func test_breakForDifferentShift_notDeducted() {
        let s = shift(id: 1, clockIn: iso(day: 22, hour: 8), clockOut: iso(day: 22, hour: 17))
        let b = breakEntry(id: 1, shiftId: 99,
                           startAt: iso(day: 22, hour: 12),
                           endAt:   iso(day: 22, hour: 12, minute: 30), paid: false)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [b], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 540)
    }

    // MARK: - Open shift (clockOut = nil)

    func test_openShift_excluded() {
        let s = shift(clockIn: iso(day: 22, hour: 8), clockOut: nil)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 0)
    }

    // MARK: - Spans midnight

    func test_spansMidnight_splitAcrossDays() {
        // 20:00 → 04:00 next day = 8h = 480 min split across two days
        // For CA rules: 4h Wed + 4h Thu → each segment < 8h → all regular
        let s = shift(clockIn: iso(day: 22, hour: 20), clockOut: iso(day: 23, hour: 4))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.totalMinutes, 480)
        XCTAssertEqual(result.overtimeMinutes, 0)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
    }

    func test_spansMidnight_longShift_dailyOT_CA() {
        // 18:00 → 08:00+1 = 14h; split: 6h Wed + 8h Thu
        // CA: Thu = exactly 8h (at threshold, no OT); Wed 6h normal
        let s = shift(clockIn: iso(day: 22, hour: 18), clockOut: iso(day: 23, hour: 8))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.totalMinutes, 840)
        // Both segments < 8h threshold → no daily OT
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    // MARK: - Week boundary

    func test_weekBoundary_OTResetsBetweenWeeks() {
        // Mon–Fri week 17 (Apr 20-24), 9h each = 2700 min; regular=2400, OT=300
        // Mon week 18 (Apr 27), 8h = 480 → starts fresh, all regular
        var shifts: [Shift] = []
        for (idx, day) in [20, 21, 22, 23, 24].enumerated() {
            shifts.append(shift(id: Int64(idx + 1),
                                clockIn:  iso(day: day, hour: 9),
                                clockOut: iso(day: day, hour: 18)))
        }
        shifts.append(shift(id: 6,
                            clockIn:  iso(day: 27, hour: 8),
                            clockOut: iso(day: 27, hour: 16)))

        let result = OvertimeCalculator.compute(shifts: shifts, breaks: [], rules: .federal)
        // Week 17: 2400 regular, 300 OT; Week 18: 480 regular
        XCTAssertEqual(result.regularMinutes, 2400 + 480)
        XCTAssertEqual(result.overtimeMinutes, 300)
    }

    // MARK: - Edge cases

    func test_emptyShifts_allZeros() {
        let result = OvertimeCalculator.compute(shifts: [], breaks: [], rules: .federal)
        XCTAssertEqual(result.regularMinutes, 0)
        XCTAssertEqual(result.overtimeMinutes, 0)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
        XCTAssertEqual(result.holidayMinutes, 0)
        XCTAssertEqual(result.totalMinutes, 0)
    }

    func test_zeroMinuteShift_excluded() {
        let s = shift(clockIn: iso(day: 22, hour: 8), clockOut: iso(day: 22, hour: 8))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 0)
    }

    func test_badISOString_shiftExcluded() {
        let s = shift(clockIn: "not-a-date", clockOut: "also-bad")
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 0)
    }

    func test_breakWithOpenEnd_notDeducted() {
        // Break with nil endAt should not deduct anything
        let s = shift(clockIn: iso(day: 22, hour: 8), clockOut: iso(day: 22, hour: 17))
        let b = BreakEntry(id: 1, employeeId: 1, shiftId: 1,
                           startAt: iso(day: 22, hour: 12), endAt: nil,
                           kind: .rest, paid: false)
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [b], rules: .federal)
        XCTAssertEqual(result.totalMinutes, 540)
    }

    func test_noWeeklyOT_threshold_zero() {
        // threshold 0 → no weekly OT applied
        let rules = OvertimeRules(weeklyOvertimeThresholdMinutes: 0)
        let s = shift(clockIn: iso(day: 20, hour: 8), clockOut: iso(day: 20, hour: 20))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: rules)
        XCTAssertEqual(result.regularMinutes, 720)
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    func test_california_exactlyAtOTThreshold_noOT() {
        // Exactly 8h → no daily OT in CA
        let s = shift(clockIn: iso(day: 21, hour: 8), clockOut: iso(day: 21, hour: 16))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.regularMinutes, 480)
        XCTAssertEqual(result.overtimeMinutes, 0)
    }

    func test_california_exactlyAtDoubleTimeThreshold_noDoubleTime() {
        // Exactly 12h → OT = 4h, double = 0
        let s = shift(clockIn: iso(day: 21, hour: 6), clockOut: iso(day: 21, hour: 18))
        let result = OvertimeCalculator.compute(shifts: [s], breaks: [], rules: .california)
        XCTAssertEqual(result.regularMinutes, 480)
        XCTAssertEqual(result.overtimeMinutes, 240)
        XCTAssertEqual(result.doubleTimeMinutes, 0)
    }
}
