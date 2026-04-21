import XCTest
@testable import Expenses

final class PerDiemCalculatorTests: XCTestCase {

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return Self.cal.date(from: comps)!
    }

    // MARK: - Day counting

    func test_sameDay_isOneDay() {
        let d = makeDate(year: 2026, month: 4, day: 20)
        XCTAssertEqual(PerDiemCalculator.days(from: d, to: d), 1)
    }

    func test_consecutiveDays_isTwoDays() {
        let start = makeDate(year: 2026, month: 4, day: 20)
        let end   = makeDate(year: 2026, month: 4, day: 21)
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 2)
    }

    func test_fiveDayTrip() {
        let start = makeDate(year: 2026, month: 4, day: 15)
        let end   = makeDate(year: 2026, month: 4, day: 19)
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 5)
    }

    func test_endBeforeStart_returnsZero() {
        let start = makeDate(year: 2026, month: 4, day: 20)
        let end   = makeDate(year: 2026, month: 4, day: 19)
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 0)
    }

    func test_monthBoundary() {
        let start = makeDate(year: 2026, month: 3, day: 30)
        let end   = makeDate(year: 2026, month: 4, day: 2)
        // March 30, 31, Apr 1, 2 = 4 days
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 4)
    }

    func test_yearBoundary() {
        let start = makeDate(year: 2025, month: 12, day: 30)
        let end   = makeDate(year: 2026, month: 1, day: 2)
        // Dec 30, 31, Jan 1, 2 = 4 days
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 4)
    }

    func test_leapYear_february29Counted() {
        let start = makeDate(year: 2024, month: 2, day: 28)
        let end   = makeDate(year: 2024, month: 3, day: 1)
        // Feb 28, 29, Mar 1 = 3 days
        XCTAssertEqual(PerDiemCalculator.days(from: start, to: end), 3)
    }

    // MARK: - Total cents

    func test_totalCents_zeroDays() {
        XCTAssertEqual(PerDiemCalculator.totalCents(days: 0, ratePerDayCents: 5000), 0)
    }

    func test_totalCents_negativeGuard() {
        XCTAssertEqual(PerDiemCalculator.totalCents(days: -1, ratePerDayCents: 5000), 0)
    }

    func test_totalCents_oneDay_50dollars() {
        XCTAssertEqual(PerDiemCalculator.totalCents(days: 1, ratePerDayCents: 5000), 5000)
    }

    func test_totalCents_fiveDays_50dollarRate() {
        XCTAssertEqual(PerDiemCalculator.totalCents(days: 5, ratePerDayCents: 5000), 25000)
    }

    func test_totalCents_gsaRate_308() {
        // GSA FY2024 M&IE: $308/day → 30800 cents × 7 days = $2156
        XCTAssertEqual(PerDiemCalculator.totalCents(days: 7, ratePerDayCents: 30800), 215600)
    }

    func test_totalCents_zeroRate() {
        XCTAssertEqual(PerDiemCalculator.totalCents(days: 10, ratePerDayCents: 0), 0)
    }

    // MARK: - Convenience calculate

    func test_calculate_fiveDayTrip() {
        let start = makeDate(year: 2026, month: 4, day: 15)
        let end   = makeDate(year: 2026, month: 4, day: 19)
        let result = PerDiemCalculator.calculate(from: start, to: end, ratePerDayCents: 5000)
        XCTAssertEqual(result.days, 5)
        XCTAssertEqual(result.totalCents, 25000)
    }

    func test_calculate_endBeforeStart_zeroBoth() {
        let start = makeDate(year: 2026, month: 4, day: 20)
        let end   = makeDate(year: 2026, month: 4, day: 18)
        let result = PerDiemCalculator.calculate(from: start, to: end, ratePerDayCents: 5000)
        XCTAssertEqual(result.days, 0)
        XCTAssertEqual(result.totalCents, 0)
    }

    func test_calculate_sameDay() {
        let d = makeDate(year: 2026, month: 1, day: 1)
        let result = PerDiemCalculator.calculate(from: d, to: d, ratePerDayCents: 7500)
        XCTAssertEqual(result.days, 1)
        XCTAssertEqual(result.totalCents, 7500)
    }
}
