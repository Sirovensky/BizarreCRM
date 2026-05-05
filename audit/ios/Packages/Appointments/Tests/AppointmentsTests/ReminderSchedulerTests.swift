import XCTest
@testable import Appointments

// MARK: - ReminderSchedulerTests
// TDD: written before ReminderScheduler was implemented.

final class ReminderSchedulerTests: XCTestCase {

    // MARK: - Helpers

    private var utcCal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Returns a Date at a specific hour-of-day in UTC on a fixed reference day.
    private func at(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 6; c.day = 15
        c.hour = hour; c.minute = minute; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return utcCal.date(from: c)!
    }

    /// Extract UTC hour from a Date.
    private func utcHour(_ date: Date) -> Int {
        utcCal.component(.hour, from: date)
    }

    // MARK: - No quiet hours

    func test_noQuietHours_naiveTime() {
        let appt = at(hour: 14) // 14:00
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 2,
            quietHours: nil
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(utcHour(result!), 12)
    }

    func test_noQuietHours_zero_offset() {
        let appt = at(hour: 10)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 0,
            quietHours: nil
        )
        // Send-time == appointment-time, which is NOT < appointment, so nil.
        XCTAssertNil(result)
    }

    func test_noQuietHours_negativeOffset_returnsNil() {
        let appt = at(hour: 10)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: -1,
            quietHours: nil
        )
        XCTAssertNil(result)
    }

    // MARK: - Quiet hours — same-day window (morning)

    func test_quietHours_naiveInWindow_pushedToEnd() {
        // Appointment at 10:00, offset 2h → naive 08:00.
        // Quiet window: 06:00–09:00 → push to 09:00.
        let appt   = at(hour: 10)
        let quiet  = QuietHoursWindow(startHour: 6, endHour: 9)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 2,
            quietHours: quiet
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(utcHour(result!), 9)
    }

    func test_quietHours_naiveOutsideWindow_unchanged() {
        // Appointment at 15:00, offset 2h → naive 13:00.
        // Quiet window: 21:00–08:00. 13:00 is outside → no shift.
        let appt   = at(hour: 15)
        let quiet  = QuietHoursWindow(startHour: 21, endHour: 8)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 2,
            quietHours: quiet
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(utcHour(result!), 13)
    }

    // MARK: - Quiet hours — overnight window

    func test_quietHours_overnight_earlyMorning_pushedOut() {
        // Appointment at 09:00, offset 4h → naive 05:00.
        // Quiet window: 22:00–07:00 (overnight) → 05:00 is in window → push to 07:00.
        let appt   = at(hour: 9)
        let quiet  = QuietHoursWindow(startHour: 22, endHour: 7)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 4,
            quietHours: quiet
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(utcHour(result!), 7)
    }

    // MARK: - Adjusted time after appointment → nil

    func test_adjustedTimeAfterAppointment_returnsNil() {
        // Appointment at 10:00, offset 24h → naive yesterday.
        // For this test simulate: appointment very soon, offset large, quiet pushes past it.
        // Appointment at 10:00, offset 9h → naive 01:00 on same day.
        // Quiet window: 00:00–10:00 (10 hours) → push to 10:00 which equals appointment → nil.
        let appt   = at(hour: 10)
        let quiet  = QuietHoursWindow(startHour: 0, endHour: 10)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 9,
            quietHours: quiet
        )
        XCTAssertNil(result, "Adjusted time equal to or after appointment should return nil")
    }

    // MARK: - 24h default offset

    func test_defaultOffset_24h() {
        let appt   = at(hour: 14)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 24,
            quietHours: nil
        )
        XCTAssertNotNil(result)
        // Should be 14:00 previous day → hour still 14.
        XCTAssertEqual(utcHour(result!), 14)
    }

    // MARK: - Large offset

    func test_largeOffset_168h_oneWeek() {
        let appt   = at(hour: 12)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 168,
            quietHours: nil
        )
        XCTAssertNotNil(result)
        // 12:00 one week earlier → still hour 12.
        XCTAssertEqual(utcHour(result!), 12)
    }

    // MARK: - Exact boundary: naive == appointment

    func test_naiveEqualsAppointment_returnsNil() {
        // If offsetHours == 0, naive == appointment.
        let appt = at(hour: 12)
        let result = ReminderScheduler.computeSendTime(
            appointmentAt: appt,
            offsetHours: 0,
            quietHours: nil
        )
        XCTAssertNil(result)
    }
}
