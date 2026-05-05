import XCTest
@testable import Appointments

// MARK: - RecurrenceExpanderTests
// TDD: written before RecurrenceExpander was implemented.

final class RecurrenceExpanderTests: XCTestCase {

    // MARK: - Helpers

    private let cal = Calendar(identifier: .gregorian)

    /// Builds a Date at the given year/month/day at noon UTC.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 12; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return cal.date(from: c)!
    }

    // MARK: - Daily

    func test_daily_count3() {
        let start = date(2025, 1, 1)
        let end   = date(2025, 1, 5)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .count(3))
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(cal.isDate(result[0], inSameDayAs: date(2025, 1, 1)))
        XCTAssertTrue(cal.isDate(result[1], inSameDayAs: date(2025, 1, 2)))
        XCTAssertTrue(cal.isDate(result[2], inSameDayAs: date(2025, 1, 3)))
    }

    func test_daily_untilDate() {
        let start = date(2025, 3, 1)
        let until = date(2025, 3, 5)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .untilDate(until))
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: until)
        XCTAssertEqual(result.count, 5)
    }

    func test_daily_forever_cappedByEndDate() {
        let start = date(2025, 1, 1)
        let end   = date(2025, 1, 31)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 31)
    }

    // MARK: - Weekly

    func test_weekly_specificWeekdays_monWedFri() {
        // Jan 6 2025 is a Monday.
        let start = date(2025, 1, 6)
        let end   = date(2025, 1, 31)
        // weekday indices: 0=Sun,1=Mon,3=Wed,5=Fri
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [1, 3, 5], endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        // Jan 6 Mon, Jan 8 Wed, Jan 10 Fri, Jan 13 Mon, Jan 15 Wed, Jan 17 Fri,
        // Jan 20 Mon, Jan 22 Wed, Jan 24 Fri, Jan 27 Mon, Jan 29 Wed, Jan 31 Fri = 12
        XCTAssertEqual(result.count, 12)
    }

    func test_weekly_noWeekdaySet_sameWeekdayAsStart() {
        // Jan 6 2025 is Monday. Jan 6, 13, 20, 27, Feb 3 = 5 Mondays.
        let start = date(2025, 1, 6)
        let end   = date(2025, 2, 3)
        let rule  = RecurrenceRule(frequency: .weekly, weekdays: [], endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 5)
        for d in result {
            let wd = cal.component(.weekday, from: d)
            XCTAssertEqual(wd, 2, "Should always be Monday (weekday=2)")
        }
    }

    func test_weekly_count() {
        let start = date(2025, 1, 6)
        let end   = date(2025, 12, 31)
        let rule  = RecurrenceRule(frequency: .weekly, weekdays: [1], endMode: .count(5))
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 5)
    }

    // MARK: - Monthly (onDayN)

    func test_monthly_onDayN_threeMonths() {
        let start = date(2025, 1, 15)
        let end   = date(2025, 3, 31)
        let rule  = RecurrenceRule(frequency: .monthly, monthlyMode: .onDayN, endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(cal.isDate(result[0], inSameDayAs: date(2025, 1, 15)))
        XCTAssertTrue(cal.isDate(result[1], inSameDayAs: date(2025, 2, 15)))
        XCTAssertTrue(cal.isDate(result[2], inSameDayAs: date(2025, 3, 15)))
    }

    func test_monthly_onNthWeekday_3rdTuesday() {
        // Jan 21 2025 = 3rd Tuesday.
        let start = date(2025, 1, 21)
        let end   = date(2025, 3, 31)
        let rule  = RecurrenceRule(frequency: .monthly, monthlyMode: .onNthWeekday, endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 3)
        // Feb 18 2025 = 3rd Tuesday, Mar 18 2025 = 3rd Tuesday.
        XCTAssertTrue(cal.isDate(result[1], inSameDayAs: date(2025, 2, 18)))
        XCTAssertTrue(cal.isDate(result[2], inSameDayAs: date(2025, 3, 18)))
    }

    // MARK: - Yearly

    func test_yearly_twoYears() {
        let start = date(2025, 6, 15)
        let end   = date(2027, 12, 31)
        let rule  = RecurrenceRule(frequency: .yearly, endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(cal.isDate(result[0], inSameDayAs: date(2025, 6, 15)))
        XCTAssertTrue(cal.isDate(result[1], inSameDayAs: date(2026, 6, 15)))
        XCTAssertTrue(cal.isDate(result[2], inSameDayAs: date(2027, 6, 15)))
    }

    // MARK: - Exception dates

    func test_exceptionDates_skipSpecificDate() {
        let start    = date(2025, 1, 1)
        let end      = date(2025, 1, 5)
        let skipDay  = date(2025, 1, 3)
        let rule     = RecurrenceRule(frequency: .daily, endMode: .forever, exceptionDates: [skipDay])
        let result   = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 4)
        let hasSkipped = result.contains { cal.isDate($0, inSameDayAs: skipDay) }
        XCTAssertFalse(hasSkipped, "Jan 3 should be skipped")
    }

    func test_multipleExceptionDates() {
        let start  = date(2025, 1, 1)
        let end    = date(2025, 1, 7)
        let skip1  = date(2025, 1, 2)
        let skip2  = date(2025, 1, 5)
        let rule   = RecurrenceRule(frequency: .daily, endMode: .forever, exceptionDates: [skip1, skip2])
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 5)
    }

    // MARK: - Until date cap

    func test_untilDate_doesNotExceedUntil() {
        let start = date(2025, 1, 1)
        let until = date(2025, 1, 10)
        let end   = date(2025, 12, 31)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .untilDate(until))
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 10)
        XCTAssertTrue(cal.isDate(result.last!, inSameDayAs: until))
    }

    // MARK: - Edge: startDate > endDate

    func test_startAfterEnd_returnsEmpty() {
        let start = date(2025, 2, 1)
        let end   = date(2025, 1, 1)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .forever)
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Count cap = 1

    func test_count1_singleOccurrence() {
        let start = date(2025, 5, 5)
        let end   = date(2025, 12, 31)
        let rule  = RecurrenceRule(frequency: .daily, endMode: .count(1))
        let result = RecurrenceExpander.expand(rule: rule, startDate: start, endDate: end)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(cal.isDate(result[0], inSameDayAs: start))
    }
}
