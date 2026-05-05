import XCTest
@testable import Appointments

// MARK: - AvailableSlotFinderTests
// TDD: written before AvailableSlotFinder was implemented.

final class AvailableSlotFinderTests: XCTestCase {

    // MARK: - Helpers

    private let cal = Calendar(identifier: .gregorian)

    /// Monday Jan 6 2025, noon local time — avoids timezone boundary shifts.
    private var monday: Date {
        var c = DateComponents()
        c.year = 2025; c.month = 1; c.day = 6
        c.hour = 12; c.minute = 0; c.second = 0
        return cal.date(from: c)!
    }

    private func time(hour: Int, minute: Int = 0) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: monday)!
    }

    private var defaultHours: BusinessHoursWeek {
        // Mon-Fri open 9–17, Sat-Sun closed (from defaultWeek).
        BusinessHoursWeek.defaultWeek
    }

    private func makeInterval(startHour: Int, endHour: Int) -> DateInterval {
        let s = cal.date(bySettingHour: startHour, minute: 0, second: 0, of: monday)!
        let e = cal.date(bySettingHour: endHour,   minute: 0, second: 0, of: monday)!
        return DateInterval(start: s, end: e)
    }

    // MARK: - Closed day

    func test_closedDay_returnsEmpty() {
        // Jan 5 2025 = Sunday (weekday 1) → closed in defaultWeek.
        var c = DateComponents()
        c.year = 2025; c.month = 1; c.day = 5; c.hour = 12
        let sunday = cal.date(from: c)!
        let result = AvailableSlotFinder.findSlots(
            on: sunday, duration: 3600, hours: defaultHours, busy: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - No busy intervals

    func test_noBusy_fullDaySlotted() {
        // 8 hours open (9–17), 60-min slots → 8 slots
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: []
        )
        XCTAssertEqual(result.count, 8)
    }

    func test_noBusy_30minSlots() {
        // 8 hours / 30 min = 16 slots
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 1800, hours: defaultHours, busy: []
        )
        XCTAssertEqual(result.count, 16)
    }

    // MARK: - Busy spans entire day

    func test_busyAllDay_returnsEmpty() {
        let allDay = makeInterval(startHour: 9, endHour: 17)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: [allDay]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Busy in middle

    func test_busyMiddle_twoFreeWindows() {
        // Busy 11–13 → free 9–11 (2 h) and 13–17 (4 h) → 2 + 4 = 6 slots of 60 min
        let busy = makeInterval(startHour: 11, endHour: 13)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: [busy]
        )
        XCTAssertEqual(result.count, 6)
        // First free slot starts at 9
        XCTAssertEqual(cal.component(.hour, from: result[0].start), 9)
        // After the break
        XCTAssertEqual(cal.component(.hour, from: result[2].start), 13)
    }

    // MARK: - Busy at start

    func test_busyStart_freeAfter() {
        // Busy 9–11 → free 11–17 (6 h) → 6 slots
        let busy = makeInterval(startHour: 9, endHour: 11)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: [busy]
        )
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(cal.component(.hour, from: result[0].start), 11)
    }

    // MARK: - Multiple busy intervals merged

    func test_multipleBusy_overlapping_merged() {
        // Busy 10–12 and 11–13 → effectively 10–13 blocked → free 9–10 (1 h) + 13–17 (4 h) = 5 slots
        let busy1 = makeInterval(startHour: 10, endHour: 12)
        let busy2 = makeInterval(startHour: 11, endHour: 13)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: [busy1, busy2]
        )
        XCTAssertEqual(result.count, 5)
    }

    // MARK: - Duration longer than any free gap

    func test_durationLongerThanFreeGap_returnsEmpty() {
        // Busy 10–16 → free 9–10 (1 h) + 16–17 (1 h).
        // 2-hour slot doesn't fit in either gap.
        let busy = makeInterval(startHour: 10, endHour: 16)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 7200, hours: defaultHours, busy: [busy]
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Busy outside business hours is ignored

    func test_busyOutsideHours_ignored() {
        let earlyBusy = makeInterval(startHour: 6, endHour: 8)
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: [earlyBusy]
        )
        XCTAssertEqual(result.count, 8) // full day unaffected
    }

    // MARK: - Slots are non-overlapping and sorted

    func test_slotsAreSortedAndNonOverlapping() {
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 3600, hours: defaultHours, busy: []
        )
        for i in 1..<result.count {
            XCTAssertGreaterThanOrEqual(result[i].start, result[i-1].end, "Slots must not overlap")
            XCTAssertLessThan(result[i-1].start, result[i].start, "Slots must be sorted")
        }
    }

    // MARK: - Slot durations are exactly as requested

    func test_slotDurationsAreExact() {
        let duration: TimeInterval = 5400 // 90 min
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: duration, hours: defaultHours, busy: []
        )
        for slot in result {
            XCTAssertEqual(slot.duration, duration, accuracy: 1)
        }
    }

    // MARK: - Zero duration returns empty

    func test_zeroDuration_returnsEmpty() {
        let result = AvailableSlotFinder.findSlots(
            on: monday, duration: 0, hours: defaultHours, busy: []
        )
        XCTAssertTrue(result.isEmpty)
    }
}
