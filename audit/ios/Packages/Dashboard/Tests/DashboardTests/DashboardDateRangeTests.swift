import XCTest
@testable import Dashboard

// MARK: - §3.1 Date-range selector tests

final class DashboardDateRangeTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    // MARK: - Preset intervals

    func test_today_fromIsStartOfDay() {
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 14, minute: 30)
        let (from, to) = DashboardDateRange.today.dateInterval(relativeTo: now, calendar: cal)
        let startOfDay = cal.startOfDay(for: now)
        XCTAssertEqual(from, startOfDay)
        XCTAssertGreaterThan(to, from)
    }

    func test_yesterday_isMinus1Day() {
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 10, minute: 0)
        let (from, _) = DashboardDateRange.yesterday.dateInterval(relativeTo: now, calendar: cal)
        let components = cal.dateComponents([.day, .month, .year], from: from)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.year, 2026)
    }

    func test_last7_fromIs6DaysAgo() {
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 9, minute: 0)
        let (from, _) = DashboardDateRange.last7.dateInterval(relativeTo: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
        XCTAssertEqual(from, expected)
    }

    func test_thisMonth_fromIsFirstOfMonth() {
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 0, minute: 0)
        let (from, _) = DashboardDateRange.thisMonth.dateInterval(relativeTo: now, calendar: cal)
        let comps = cal.dateComponents([.day, .month, .year], from: from)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.year, 2026)
    }

    func test_thisYear_fromIsJan1() {
        let now = makeDate(year: 2026, month: 4, day: 26, hour: 0, minute: 0)
        let (from, _) = DashboardDateRange.thisYear.dateInterval(relativeTo: now, calendar: cal)
        let comps = cal.dateComponents([.day, .month, .year], from: from)
        XCTAssertEqual(comps.day, 1)
        XCTAssertEqual(comps.month, 1)
        XCTAssertEqual(comps.year, 2026)
    }

    func test_allCases_fromIsBeforeTo() {
        let now = makeDate(year: 2026, month: 4, day: 15, hour: 12, minute: 0)
        for range in DashboardDateRange.allCases where range != .custom {
            let (from, to) = range.dateInterval(relativeTo: now, calendar: cal)
            XCTAssertLessThanOrEqual(from, to, "Range \(range.rawValue) from should be ≤ to")
        }
    }

    // MARK: - Store persistence

    func test_store_roundTrips_range() {
        let defaults = UserDefaults(suiteName: "test.dateRange.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        store.saveRange(.lastMonth)
        XCTAssertEqual(store.loadRange(), .lastMonth)
        store.saveRange(.thisYear)
        XCTAssertEqual(store.loadRange(), .thisYear)
    }

    func test_store_unknownKey_defaultsToToday() {
        let defaults = UserDefaults(suiteName: "test.dateRange.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        // No value saved yet — should return .today
        XCTAssertEqual(store.loadRange(), .today)
    }

    func test_store_roundTrips_customDates() {
        let defaults = UserDefaults(suiteName: "test.dateRange.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        let from = makeDate(year: 2026, month: 1, day: 1, hour: 0, minute: 0)
        let to   = makeDate(year: 2026, month: 3, day: 31, hour: 23, minute: 59)
        store.saveCustomDates(from: from, to: to)
        let (loadedFrom, loadedTo) = store.loadCustomDates()
        XCTAssertEqual(loadedFrom.timeIntervalSince1970, from.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loadedTo.timeIntervalSince1970, to.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - ViewModel

    @MainActor
    func test_viewModel_select_callsOnChange() async {
        let defaults = UserDefaults(suiteName: "test.vm.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        let vm = DashboardDateRangeViewModel(store: store)

        var capturedRange: DashboardDateRange?
        vm.onChange = { range, _, _ in capturedRange = range }
        vm.select(.last7)
        XCTAssertEqual(capturedRange, .last7)
    }

    @MainActor
    func test_viewModel_custom_showsPicker() {
        let defaults = UserDefaults(suiteName: "test.vm2.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        let vm = DashboardDateRangeViewModel(store: store)
        vm.select(.custom)
        XCTAssertTrue(vm.isShowingCustomPicker)
    }

    @MainActor
    func test_viewModel_effectiveInterval_returnsPreset() {
        let defaults = UserDefaults(suiteName: "test.vm3.\(UUID())")!
        let store = DashboardDateRangeStore(defaults: defaults)
        let vm = DashboardDateRangeViewModel(store: store)
        vm.selectedRange = .last7
        let (from, to) = vm.effectiveInterval
        XCTAssertLessThan(from, to)
    }

    // MARK: - DisplayName

    func test_allCases_haveNonEmptyDisplayName() {
        for range in DashboardDateRange.allCases {
            XCTAssertFalse(range.displayName.isEmpty, "Range \(range.rawValue) has empty displayName")
        }
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return cal.date(from: comps)!
    }
}
