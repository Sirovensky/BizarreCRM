import XCTest
@testable import Settings

// MARK: - HoursCalculatorTests

final class HoursCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private static let tz = TimeZone(identifier: "America/New_York")!

    /// Makes a Date in America/New_York for a given hour on 2026-04-20 (Monday, weekday 2).
    private func makeDate(weekday: Int = 2, hour: Int, minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        // Reference Monday 2026-04-20 is weekday 2 in the Gregorian calendar.
        // Offset by (weekday - 2) days from that Monday.
        var dc = DateComponents(year: 2026, month: 4, day: 20 + (weekday - 2), hour: hour, minute: minute)
        return cal.date(from: dc)!
    }

    private func makeWeek(
        openHour: Int = 9, openMin: Int = 0,
        closeHour: Int = 17, closeMin: Int = 0,
        breaks: [TimeBreak]? = nil,
        openWeekdays: Set<Int> = [2, 3, 4, 5, 6]   // Mon-Fri
    ) -> BusinessHoursWeek {
        let days = (1...7).map { wd -> BusinessDay in
            let open = openWeekdays.contains(wd)
            return BusinessDay(
                weekday: wd,
                isOpen: open,
                openAt: open ? DateComponents(hour: openHour, minute: openMin) : nil,
                closeAt: open ? DateComponents(hour: closeHour, minute: closeMin) : nil,
                breaks: open ? breaks : nil
            )
        }
        return BusinessHoursWeek(days: days)
    }

    // MARK: - Basic open/closed

    func test_open_duringBusinessHours() {
        let week = makeWeek()
        let date = makeDate(weekday: 2, hour: 10) // Mon 10:00

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open, got \(result)")
        }
    }

    func test_closed_beforeOpen() {
        let week = makeWeek()
        let date = makeDate(weekday: 2, hour: 8) // Mon 8:00 (before 9:00 open)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed(let opensAt) = result {
            XCTAssertNotNil(opensAt)
        } else {
            XCTFail("Expected .closed, got \(result)")
        }
    }

    func test_closed_afterClose() {
        let week = makeWeek()
        let date = makeDate(weekday: 2, hour: 18) // Mon 18:00 (after 17:00 close)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed, got \(result)")
        }
    }

    func test_closed_onSunday() {
        let week = makeWeek()
        let date = makeDate(weekday: 1, hour: 12) // Sunday noon

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed on Sunday, got \(result)")
        }
    }

    func test_closed_onSaturday() {
        let week = makeWeek()
        let date = makeDate(weekday: 7, hour: 12) // Saturday noon

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed on Saturday, got \(result)")
        }
    }

    // MARK: - Exact boundary

    func test_exactOpenBoundary() {
        let week = makeWeek(openHour: 9)
        let date = makeDate(weekday: 2, hour: 9, minute: 0) // exactly open

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open at exact open boundary, got \(result)")
        }
    }

    func test_exactCloseBoundary() {
        let week = makeWeek(closeHour: 17)
        let date = makeDate(weekday: 2, hour: 17, minute: 0) // exactly at close (exclusive)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed at exact close boundary, got \(result)")
        }
    }

    // MARK: - Break logic

    func test_onBreak_duringLunch() {
        let lunch = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0),
            label: "Lunch"
        )
        let week = makeWeek(breaks: [lunch])
        let date = makeDate(weekday: 2, hour: 12, minute: 30) // Mon 12:30

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .onBreak(let endsAt) = result {
            XCTAssertNotNil(endsAt)
        } else {
            XCTFail("Expected .onBreak, got \(result)")
        }
    }

    func test_open_afterBreak() {
        let lunch = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0),
            label: "Lunch"
        )
        let week = makeWeek(breaks: [lunch])
        let date = makeDate(weekday: 2, hour: 13, minute: 1) // 13:01 — after break

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open after break, got \(result)")
        }
    }

    func test_exactBreakStartBoundary() {
        let lunch = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0),
            label: "Lunch"
        )
        let week = makeWeek(breaks: [lunch])
        let date = makeDate(weekday: 2, hour: 12, minute: 0) // exactly break start

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .onBreak = result { /* pass */ } else {
            XCTFail("Expected .onBreak at break start, got \(result)")
        }
    }

    func test_exactBreakEndBoundary() {
        let lunch = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0),
            label: "Lunch"
        )
        let week = makeWeek(breaks: [lunch])
        let date = makeDate(weekday: 2, hour: 13, minute: 0) // exactly break end (exclusive)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open at break end boundary, got \(result)")
        }
    }

    // MARK: - Midnight span

    func test_midnightSpan_openBeforeMidnight() {
        // Bar open 22:00 → 02:00
        let week = makeWeek(openHour: 22, closeHour: 2, openWeekdays: [2, 3, 4, 5, 6, 7])
        let date = makeDate(weekday: 2, hour: 23) // Mon 23:00

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open during midnight-spanning hours, got \(result)")
        }
    }

    func test_midnightSpan_closedAfterMidnight() {
        // Open 22:00 → 02:00; at 03:00 should be closed
        let week = makeWeek(openHour: 22, closeHour: 2, openWeekdays: [2, 3, 4, 5, 6, 7])
        let date = makeDate(weekday: 2, hour: 3) // Tue 03:00 (different day check)
        // Note: this hits Tuesday's own open period at 22:00; at 03:00 Tue it is before Tue's open.

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed at 03:00 (before 22:00 open), got \(result)")
        }
    }

    // MARK: - Holiday overrides

    func test_holiday_closedOverridesOpenDay() {
        let week = makeWeek()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        // Monday 2026-04-20 = weekday 2 = normally open
        let holidayDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let holiday = HolidayException(
            id: "h1",
            date: holidayDate,
            isOpen: false,
            reason: "Office picnic",
            recurring: .once
        )
        let date = makeDate(weekday: 2, hour: 10) // Mon 10:00 — normally open

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [holiday], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed due to holiday override, got \(result)")
        }
    }

    func test_holiday_specialHoursOverride() {
        let week = makeWeek()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let holidayDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let holiday = HolidayException(
            id: "h2",
            date: holidayDate,
            isOpen: true,
            openAt: DateComponents(hour: 10, minute: 0),
            closeAt: DateComponents(hour: 14, minute: 0),
            reason: "Short day",
            recurring: .once
        )
        // At 13:00 — within special hours
        let date = makeDate(weekday: 2, hour: 13)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [holiday], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open during special holiday hours, got \(result)")
        }
    }

    func test_holiday_specialHoursClosedOutside() {
        let week = makeWeek()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let holidayDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let holiday = HolidayException(
            id: "h3",
            date: holidayDate,
            isOpen: true,
            openAt: DateComponents(hour: 10, minute: 0),
            closeAt: DateComponents(hour: 14, minute: 0),
            reason: "Short day",
            recurring: .once
        )
        // At 15:00 — outside special hours
        let date = makeDate(weekday: 2, hour: 15)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [holiday], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed outside special holiday hours, got \(result)")
        }
    }

    func test_yearlyHoliday_matchesSameMonthDay() {
        let week = makeWeek(openWeekdays: Set(1...7)) // open every day
        // Christmas 2025 → set as yearly
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let christmasBase = cal.date(from: DateComponents(year: 2025, month: 12, day: 25))!
        let holiday = HolidayException(
            id: "christmas",
            date: christmasBase,
            isOpen: false,
            reason: "Christmas",
            recurring: .yearly
        )
        // Check Christmas 2026 (different year)
        let christmas2026 = cal.date(from: DateComponents(year: 2026, month: 12, day: 25, hour: 10))!

        let result = HoursCalculator.currentStatus(at: christmas2026, week: week, holidays: [holiday], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed on yearly holiday, got \(result)")
        }
    }

    func test_yearlyHoliday_doesNotMatchDifferentDay() {
        let week = makeWeek(openWeekdays: Set(1...7))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let christmasBase = cal.date(from: DateComponents(year: 2025, month: 12, day: 25))!
        let holiday = HolidayException(
            id: "christmas",
            date: christmasBase,
            isOpen: false,
            reason: "Christmas",
            recurring: .yearly
        )
        // December 26th — should NOT match
        let dec26 = cal.date(from: DateComponents(year: 2026, month: 12, day: 26, hour: 10))!

        let result = HoursCalculator.currentStatus(at: dec26, week: week, holidays: [holiday], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open on Dec 26 (not the holiday), got \(result)")
        }
    }

    func test_monthlyHoliday_matchesSameDayOfMonth() {
        let week = makeWeek(openWeekdays: Set(1...7))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let holiday = HolidayException(
            id: "monthly15",
            date: base,
            isOpen: false,
            reason: "Monthly closure",
            recurring: .monthly
        )
        // April 15 (different month)
        let apr15 = cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 10))!

        let result = HoursCalculator.currentStatus(at: apr15, week: week, holidays: [holiday], timezone: Self.tz)

        if case .closed = result { /* pass */ } else {
            XCTFail("Expected .closed on monthly holiday, got \(result)")
        }
    }

    // MARK: - Next open computation

    func test_nextOpen_foundOnMonday() {
        // All week closed except Mon
        let week = makeWeek(openWeekdays: [2])
        // Start from Sunday
        let sunday = makeDate(weekday: 1, hour: 12)

        let result = HoursCalculator.currentStatus(at: sunday, week: week, holidays: [], timezone: Self.tz)

        if case .closed(let opensAt) = result {
            XCTAssertNotNil(opensAt)
            // Should be the next Monday morning
            if let opensAt {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = Self.tz
                XCTAssertEqual(cal.component(.weekday, from: opensAt), 2) // Monday
            }
        } else {
            XCTFail("Expected .closed with nextOpen on Monday, got \(result)")
        }
    }

    func test_closesAt_returnsCorrectTime() {
        let week = makeWeek(closeHour: 17, closeMin: 30)
        let date = makeDate(weekday: 2, hour: 10) // Mon 10:00

        if case .open(let closesAt) = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz) {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = Self.tz
            XCTAssertEqual(cal.component(.hour, from: closesAt), 17)
            XCTAssertEqual(cal.component(.minute, from: closesAt), 30)
        } else {
            XCTFail("Expected .open with closesAt")
        }
    }

    // MARK: - Timezone isolation

    func test_timezoneAware_differentFromUTC() {
        // America/New_York is UTC-4 in April. 13:00 UTC = 09:00 EDT.
        // Shop opens at 09:00 → should be exactly at open.
        let week = makeWeek(openHour: 9)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        // 13:00 UTC on 2026-04-20 = 09:00 EDT
        let utcDate = utcCal.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 13, minute: 0))!

        let result = HoursCalculator.currentStatus(at: utcDate, week: week, holidays: [], timezone: Self.tz)

        if case .open = result { /* pass */ } else {
            XCTFail("Expected .open when accounting for EDT offset, got \(result)")
        }
    }

    // MARK: - Full-week-closed edge case

    func test_allDaysClosed_returnsClosedWithNilOpensAt() {
        let week = makeWeek(openWeekdays: [])
        let date = makeDate(weekday: 2, hour: 10)

        let result = HoursCalculator.currentStatus(at: date, week: week, holidays: [], timezone: Self.tz)

        if case .closed(let opensAt) = result {
            XCTAssertNil(opensAt, "No open day found, opensAt should be nil")
        } else {
            XCTFail("Expected .closed, got \(result)")
        }
    }
}

// MARK: - HoursValidatorTests

final class HoursValidatorTests: XCTestCase {

    private static let tz = TimeZone(identifier: "America/New_York")!

    private func makeDate(hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        return cal.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: hour))!
    }

    func test_validSlot_returnsTrue() {
        let week = BusinessHoursWeek.defaultWeek
        let slot = makeDate(hour: 10) // Mon 10:00 — within Mon-Fri 9-17

        XCTAssertTrue(HoursValidator.isSlotValid(slot, hoursWeek: week, holidays: [], timezone: Self.tz))
    }

    func test_closedSlot_returnsFalse() {
        let week = BusinessHoursWeek.defaultWeek
        let slot = makeDate(hour: 20) // Mon 20:00 — after hours

        XCTAssertFalse(HoursValidator.isSlotValid(slot, hoursWeek: week, holidays: [], timezone: Self.tz))
    }

    func test_holidayClosure_returnsFalse() {
        let week = BusinessHoursWeek.defaultWeek
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.tz
        let holidayDate = cal.date(from: DateComponents(year: 2026, month: 4, day: 20))!
        let holiday = HolidayException(id: "h", date: holidayDate, isOpen: false, reason: "Closed", recurring: .once)

        let slot = makeDate(hour: 10) // would normally be open

        XCTAssertFalse(HoursValidator.isSlotValid(slot, hoursWeek: week, holidays: [holiday], timezone: Self.tz))
    }

    func test_breakSlot_returnsFalse() {
        let lunch = TimeBreak(
            startAt: DateComponents(hour: 12, minute: 0),
            endAt: DateComponents(hour: 13, minute: 0)
        )
        let days = (1...7).map { wd -> BusinessDay in
            let open = wd >= 2 && wd <= 6
            return BusinessDay(
                weekday: wd,
                isOpen: open,
                openAt: open ? DateComponents(hour: 9, minute: 0) : nil,
                closeAt: open ? DateComponents(hour: 17, minute: 0) : nil,
                breaks: open ? [lunch] : nil
            )
        }
        let week = BusinessHoursWeek(days: days)
        let slot = makeDate(hour: 12) // Mon 12:00 = break start

        XCTAssertFalse(HoursValidator.isSlotValid(slot, hoursWeek: week, holidays: [], timezone: Self.tz))
    }
}

// MARK: - BusinessHoursEditorViewModelTests

@MainActor
final class BusinessHoursEditorViewModelTests: XCTestCase {

    private func makeVM() -> BusinessHoursEditorViewModel {
        BusinessHoursEditorViewModel(
            repository: StubHoursRepository(),
            timezone: TimeZone(identifier: "America/New_York")!
        )
    }

    func test_copyMondayToWeekdays() {
        let vm = makeVM()
        // Set Monday to 8-18
        vm.setOpenTime(DateComponents(hour: 8, minute: 0), for: 2)
        vm.setCloseTime(DateComponents(hour: 18, minute: 0), for: 2)

        vm.copyMondayToWeekdays()

        for weekday in 3...6 {
            let day = vm.week.day(for: weekday)
            XCTAssertEqual(day?.openAt?.hour, 8, "Weekday \(weekday) openAt should be 8")
            XCTAssertEqual(day?.closeAt?.hour, 18, "Weekday \(weekday) closeAt should be 18")
        }
    }

    func test_copySaturdayToSunday() {
        let vm = makeVM()
        vm.setOpen(true, for: 7)
        vm.setOpenTime(DateComponents(hour: 10, minute: 0), for: 7)
        vm.setCloseTime(DateComponents(hour: 15, minute: 0), for: 7)

        vm.copySaturdayToSunday()

        let sunday = vm.week.day(for: 1)
        XCTAssertTrue(sunday?.isOpen == true)
        XCTAssertEqual(sunday?.openAt?.hour, 10)
        XCTAssertEqual(sunday?.closeAt?.hour, 15)
    }

    func test_addBreak_appendsNewBreak() {
        let vm = makeVM()
        vm.addBreak(to: 2)

        let day = vm.week.day(for: 2)
        XCTAssertEqual(day?.breaks?.count, 1)
    }

    func test_removeBreak_removesById() {
        let vm = makeVM()
        vm.addBreak(to: 2)
        let br = vm.week.day(for: 2)!.breaks!.first!

        vm.removeBreak(id: br.id, from: 2)

        XCTAssertTrue(vm.week.day(for: 2)?.breaks == nil || vm.week.day(for: 2)?.breaks?.isEmpty == true)
    }

    func test_setOpen_false_clearsOpenClose() {
        let vm = makeVM()
        vm.setOpen(false, for: 2)

        let day = vm.week.day(for: 2)
        XCTAssertFalse(day?.isOpen == true)
        XCTAssertNil(day?.openAt)
        XCTAssertNil(day?.closeAt)
    }

    func test_save_callsRepository() async {
        let stub = StubHoursRepository()
        let vm = BusinessHoursEditorViewModel(repository: stub, timezone: .current)

        await vm.save()

        XCTAssertTrue(stub.saveWeekCalled)
    }

    func test_save_setsErrorOnFailure() async {
        let stub = StubHoursRepository(shouldFail: true)
        let vm = BusinessHoursEditorViewModel(repository: stub, timezone: .current)

        await vm.save()

        XCTAssertNotNil(vm.errorMessage)
    }
}

// MARK: - HolidayEditorViewModelTests

@MainActor
final class HolidayEditorViewModelTests: XCTestCase {

    func test_isValid_requiresNonEmptyReason() {
        let stub = StubHoursRepository()
        let vm = HolidayEditorViewModel(mode: .create, repository: stub)
        vm.reason = ""
        XCTAssertFalse(vm.isValid)
        vm.reason = "Christmas"
        XCTAssertTrue(vm.isValid)
    }

    func test_save_create_callsCreateHoliday() async {
        let stub = StubHoursRepository()
        let vm = HolidayEditorViewModel(mode: .create, repository: stub)
        vm.reason = "Test Holiday"

        await vm.save()

        XCTAssertTrue(stub.createHolidayCalled)
    }

    func test_save_edit_callsUpdateHoliday() async {
        let stub = StubHoursRepository()
        let existing = HolidayException(id: "h1", date: Date(), isOpen: false, reason: "Old", recurring: .once)
        let vm = HolidayEditorViewModel(mode: .edit(existing), repository: stub)
        vm.reason = "Updated Holiday"

        await vm.save()

        XCTAssertTrue(stub.updateHolidayCalled)
    }

    func test_save_blankReason_setsError() async {
        let stub = StubHoursRepository()
        let vm = HolidayEditorViewModel(mode: .create, repository: stub)
        vm.reason = "  "

        await vm.save()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(stub.createHolidayCalled)
    }
}

// MARK: - HolidayPresets Tests

final class HolidayPresetsTests: XCTestCase {

    func test_allUSHolidays_count() {
        XCTAssertEqual(HolidayPresets.usHolidays.count, 9)
    }

    func test_makeException_producesCorrectMonth() {
        let newYear = HolidayPresets.usHolidays.first { $0.id == "us.newyear" }!
        let exception = HolidayPresets.makeException(from: newYear, year: 2026)

        XCTAssertNotNil(exception)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.month, from: exception!.date), 1)
        XCTAssertEqual(cal.component(.day, from: exception!.date), 1)
    }

    func test_allExceptions_returnsNine() {
        let all = HolidayPresets.allExceptions()
        XCTAssertEqual(all.count, 9)
    }

    func test_makeException_recurringIsYearly() {
        let christmas = HolidayPresets.usHolidays.first { $0.id == "us.christmas" }!
        let exception = HolidayPresets.makeException(from: christmas)!
        XCTAssertEqual(exception.recurring, .yearly)
    }

    func test_makeException_isClosedByDefault() {
        let preset = HolidayPresets.usHolidays[0]
        let exception = HolidayPresets.makeException(from: preset)!
        XCTAssertFalse(exception.isOpen)
    }
}

// MARK: - Stub repository

final class StubHoursRepository: HoursRepository, @unchecked Sendable {
    let shouldFail: Bool
    var saveWeekCalled = false
    var createHolidayCalled = false
    var updateHolidayCalled = false

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func fetchHoursWeek() async throws -> BusinessHoursWeek { .defaultWeek }
    func saveHoursWeek(_ week: BusinessHoursWeek) async throws -> BusinessHoursWeek {
        if shouldFail { throw URLError(.badServerResponse) }
        saveWeekCalled = true
        return week
    }
    func fetchHolidays() async throws -> [HolidayException] { [] }
    func createHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        if shouldFail { throw URLError(.badServerResponse) }
        createHolidayCalled = true
        return holiday
    }
    func updateHoliday(_ holiday: HolidayException) async throws -> HolidayException {
        if shouldFail { throw URLError(.badServerResponse) }
        updateHolidayCalled = true
        return holiday
    }
    func deleteHoliday(id: String) async throws {
        if shouldFail { throw URLError(.badServerResponse) }
    }
}
