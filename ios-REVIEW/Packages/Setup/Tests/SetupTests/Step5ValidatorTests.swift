import XCTest
@testable import Setup

final class Step5ValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func day(_ weekday: Int, isOpen: Bool, open: (Int, Int) = (9, 0), close: (Int, Int) = (18, 0)) -> BusinessDay {
        BusinessDay(
            weekday: weekday,
            isOpen: isOpen,
            openAt: DateComponents(hour: open.0, minute: open.1),
            closeAt: DateComponents(hour: close.0, minute: close.1)
        )
    }

    private var defaultHours: [BusinessDay] { BusinessDay.defaults }

    // MARK: - isNextEnabled

    func testIsNextEnabled_defaultHours_returnsTrue() {
        XCTAssertTrue(Step5Validator.isNextEnabled(hours: defaultHours))
    }

    func testIsNextEnabled_allClosed_returnsFalse() {
        let closed = (1...7).map { day($0, isOpen: false) }
        XCTAssertFalse(Step5Validator.isNextEnabled(hours: closed))
    }

    func testIsNextEnabled_oneDayOpen_returnsTrue() {
        var hours = (1...7).map { day($0, isOpen: false) }
        hours[0] = day(1, isOpen: true)
        XCTAssertTrue(Step5Validator.isNextEnabled(hours: hours))
    }

    // MARK: - validate

    func testValidate_defaultHours_isValid() {
        let result = Step5Validator.validate(hours: defaultHours)
        XCTAssertTrue(result.isValid)
    }

    func testValidate_emptyArray_isInvalid() {
        let result = Step5Validator.validate(hours: [])
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidate_allClosed_isInvalid() {
        let closed = (1...7).map { day($0, isOpen: false) }
        let result = Step5Validator.validate(hours: closed)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidate_openTimeAfterClose_isInvalid() {
        let badDay = BusinessDay(
            weekday: 1,
            isOpen: true,
            openAt: DateComponents(hour: 20, minute: 0),
            closeAt: DateComponents(hour: 8, minute: 0)
        )
        let hours = [badDay] + (2...7).map { day($0, isOpen: false) }
        let result = Step5Validator.validate(hours: hours)
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidate_openTimeEqualsClose_isInvalid() {
        let equalDay = BusinessDay(
            weekday: 1,
            isOpen: true,
            openAt: DateComponents(hour: 9, minute: 0),
            closeAt: DateComponents(hour: 9, minute: 0)
        )
        let hours = [equalDay] + (2...7).map { day($0, isOpen: false) }
        let result = Step5Validator.validate(hours: hours)
        XCTAssertFalse(result.isValid)
    }

    func testValidate_closedDayTimeOrderIgnored() {
        // Closed days don't matter for time order
        let closedBadTimes = BusinessDay(
            weekday: 1,
            isOpen: false,
            openAt: DateComponents(hour: 20, minute: 0),
            closeAt: DateComponents(hour: 8, minute: 0)
        )
        let openGoodDay = day(2, isOpen: true, open: (9, 0), close: (18, 0))
        let result = Step5Validator.validate(hours: [closedBadTimes, openGoodDay])
        XCTAssertTrue(result.isValid)
    }
}
