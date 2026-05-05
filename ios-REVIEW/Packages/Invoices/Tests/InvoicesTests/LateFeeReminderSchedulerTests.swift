import XCTest
@testable import Invoices

final class LateFeeReminderSchedulerTests: XCTestCase {

    private var utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_nilDueDate_returnsNil() {
        XCTAssertNil(LateFeeReminderScheduler.computeWindow(
            dueDate: nil, gracePeriodDays: 7, asOf: date(2024, 1, 1), calendar: utc
        ))
    }

    func test_inWindow_isInWindow() {
        // due Jan 1, grace 7 → fee starts Jan 9. lead 2 → sendOn = Jan 7.
        let win = LateFeeReminderScheduler.computeWindow(
            dueDate: date(2024, 1, 1), gracePeriodDays: 7, leadDays: 2,
            asOf: date(2024, 1, 8), calendar: utc
        )!
        XCTAssertEqual(win.leadDays, 2)
        XCTAssertTrue(win.isInWindow)
    }

    func test_beforeWindow_isNotInWindow() {
        let win = LateFeeReminderScheduler.computeWindow(
            dueDate: date(2024, 1, 1), gracePeriodDays: 7, leadDays: 2,
            asOf: date(2024, 1, 5), calendar: utc
        )!
        XCTAssertFalse(win.isInWindow)
    }

    func test_pastFeeStart_returnsNil() {
        XCTAssertNil(LateFeeReminderScheduler.computeWindow(
            dueDate: date(2024, 1, 1), gracePeriodDays: 7,
            asOf: date(2024, 2, 1), calendar: utc
        ))
    }

    func test_leadDays_clampedToBounds() {
        let win = LateFeeReminderScheduler.computeWindow(
            dueDate: date(2024, 1, 1), gracePeriodDays: 7, leadDays: 99,
            asOf: date(2024, 1, 8), calendar: utc
        )!
        XCTAssertEqual(win.leadDays, 3)
    }
}
