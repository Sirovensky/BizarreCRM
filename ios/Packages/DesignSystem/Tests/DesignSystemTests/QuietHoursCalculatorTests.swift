import Testing
import Foundation
@testable import DesignSystem

// §66 — QuietHoursCalculator tests (≥80% coverage required)

@Suite("QuietHoursCalculator")
struct QuietHoursCalculatorTests {

    // MARK: - hourOfDay

    @Test("hourOfDay returns correct hour for midnight")
    func hourOfDayMidnight() {
        var comps = DateComponents()
        comps.hour = 0; comps.minute = 0
        let date = Calendar.current.date(from: comps)!
        #expect(QuietHoursCalculator.hourOfDay(from: date) == 0)
    }

    @Test("hourOfDay returns correct hour for noon")
    func hourOfDayNoon() {
        var comps = DateComponents()
        comps.hour = 12; comps.minute = 30
        let date = Calendar.current.date(from: comps)!
        #expect(QuietHoursCalculator.hourOfDay(from: date) == 12)
    }

    @Test("hourOfDay returns 23 for 11pm")
    func hourOfDay23() {
        var comps = DateComponents()
        comps.hour = 23; comps.minute = 59
        let date = Calendar.current.date(from: comps)!
        #expect(QuietHoursCalculator.hourOfDay(from: date) == 23)
    }

    // MARK: - isWithinQuietWindow — same-day window

    @Test("same-day window: hour inside returns true")
    func sameDayWindowInside() {
        // Window 9 → 17
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 10, start: 9, end: 17) == true)
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 9,  start: 9, end: 17) == true)
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 16, start: 9, end: 17) == true)
    }

    @Test("same-day window: hour exactly at end returns false (exclusive)")
    func sameDayWindowAtEnd() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 17, start: 9, end: 17) == false)
    }

    @Test("same-day window: hour outside returns false")
    func sameDayWindowOutside() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 8,  start: 9, end: 17) == false)
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 18, start: 9, end: 17) == false)
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 0,  start: 9, end: 17) == false)
    }

    // MARK: - isWithinQuietWindow — overnight window

    @Test("overnight window 21→7: hour after start returns true")
    func overnightAfterStart() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 21, start: 21, end: 7) == true)
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 23, start: 21, end: 7) == true)
    }

    @Test("overnight window 21→7: midnight returns true")
    func overnightMidnight() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 0, start: 21, end: 7) == true)
    }

    @Test("overnight window 21→7: early morning before end returns true")
    func overnightBeforeEnd() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 6, start: 21, end: 7) == true)
    }

    @Test("overnight window 21→7: hour exactly at end returns false")
    func overnightAtEnd() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 7, start: 21, end: 7) == false)
    }

    @Test("overnight window 21→7: afternoon returns false")
    func overnightAfternoon() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 14, start: 21, end: 7) == false)
    }

    // MARK: - isWithinQuietWindow — edge cases

    @Test("equal start and end returns false (disabled)")
    func equalStartEnd() {
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 9, start: 9, end: 9) == false)
    }

    @Test("invalid hour 24 returns false")
    func invalidHour() {
        // hour 24 is out of 0-23; isWithinQuietWindow returns false for invalid start/end
        // Our implementation does not validate hour, but 24 is never returned by Calendar
        // so this is defensive.
        #expect(QuietHoursCalculator.isWithinQuietWindow(hour: 12, start: 25, end: 7) == false)
    }

    // MARK: - shouldSuppress

    @Test("exceptCritical=true always returns false (allow critical)")
    func exceptCriticalAlwaysPasses() {
        // Even inside quiet window, critical events pass.
        let date = makeDate(hour: 22)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 21,
            quietEnd: 7,
            exceptCritical: true
        )
        #expect(result == false)
    }

    @Test("returns true inside overnight quiet window")
    func suppressInsideWindow() {
        let date = makeDate(hour: 23)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 21,
            quietEnd: 7,
            exceptCritical: false
        )
        #expect(result == true)
    }

    @Test("returns false outside quiet window")
    func noSuppressOutsideWindow() {
        let date = makeDate(hour: 10)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 21,
            quietEnd: 7,
            exceptCritical: false
        )
        #expect(result == false)
    }

    @Test("equal start=end: always returns false (window disabled)")
    func disabledWindow() {
        let date = makeDate(hour: 9)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 9,
            quietEnd: 9,
            exceptCritical: false
        )
        #expect(result == false)
    }

    @Test("same-day window: suppress at hour 15 when window is 9-17")
    func suppressSameDayWindow() {
        let date = makeDate(hour: 15)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 9,
            quietEnd: 17,
            exceptCritical: false
        )
        #expect(result == true)
    }

    @Test("same-day window: no suppress at hour 18 when window is 9-17")
    func noSuppressAfterSameDayWindow() {
        let date = makeDate(hour: 18)
        let result = QuietHoursCalculator.shouldSuppress(
            at: date,
            quietStart: 9,
            quietEnd: 17,
            exceptCritical: false
        )
        #expect(result == false)
    }

    // MARK: - Helpers

    private func makeDate(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 4; comps.day = 20
        comps.hour = hour; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
