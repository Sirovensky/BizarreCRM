import XCTest
@testable import Reports

// MARK: - ReportsViewModelTests
// Tests that:
// - Range picker changes trigger correct endpoint parameters.
// - loadAll() populates all data fields.
// - Error path sets errorMessage without crashing.

@MainActor
final class ReportsViewModelTests: XCTestCase {

    // MARK: - Default preset

    func test_defaultPreset_isThirtyDays() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        XCTAssertEqual(vm.selectedPreset, .thirtyDays)
    }

    // MARK: - Date range strings

    func test_sevenDayPreset_setsCorrectFromDate() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.selectedPreset = .sevenDays
        // from should be ~7 days ago
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let fromDate = isoFmt.date(from: vm.fromDateString)!
        let diff = Date().timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 7.0, accuracy: 1.0)
    }

    func test_ninetyDayPreset_setsCorrectFromDate() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.selectedPreset = .ninetyDays
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let fromDate = isoFmt.date(from: vm.fromDateString)!
        let diff = Date().timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 90.0, accuracy: 1.0)
    }

    func test_customRange_setsCustomDates() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        let from = Date(timeIntervalSinceNow: -86400 * 14)
        let to   = Date()
        vm.applyCustomRange(from: from, to: to)
        XCTAssertEqual(vm.selectedPreset, .custom)
        XCTAssertFalse(vm.fromDateString.isEmpty)
        XCTAssertFalse(vm.toDateString.isEmpty)
    }

    // MARK: - loadAll populates data

    func test_loadAll_populatesRevenue() async {
        let stub = StubReportsRepository()
        await stub.setRevenueResult(.success([RevenuePoint.fixture()]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenue.count, 1)
    }

    func test_loadAll_populatesTicketsByStatus() async {
        let stub = StubReportsRepository()
        await stub.setTicketsResult(.success([.fixture()]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.ticketsByStatus.count, 1)
    }

    func test_loadAll_populatesAvgTicketValue() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.avgTicketValue)
    }

    func test_loadAll_populatesEmployees() async {
        let stub = StubReportsRepository()
        await stub.setEmployeesResult(.success([.fixture()]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.employeePerf.count, 1)
    }

    func test_loadAll_populatesCSAT() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.csatScore)
    }

    func test_loadAll_populatesNPS() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.npsScore)
    }

    func test_loadAll_setsLastSyncedAt() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        XCTAssertNil(vm.lastSyncedAt)
        await vm.loadAll()
        XCTAssertNotNil(vm.lastSyncedAt)
    }

    func test_loadAll_setIsLoading_false_afterComplete() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Error path

    func test_loadAll_revenueError_setsErrorMessage() async {
        let stub = StubReportsRepository()
        await stub.setRevenueResult(.failure(RepoTestError.bang))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Hero tile computed

    func test_revenueTotalCents_sumsAllPoints() async {
        let stub = StubReportsRepository()
        await stub.setRevenueResult(.success([
            RevenuePoint.fixture(id: 1, amountCents: 5000),
            RevenuePoint.fixture(id: 2, amountCents: 3000)
        ]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenueTotalCents, 8000)
        XCTAssertEqual(vm.revenueTotalDollars, 80.0, accuracy: 0.001)
    }

    // MARK: - groupBy passthrough

    func test_loadAll_passesGroupByDay() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        let lastGroupBy = await stub.revenueLastGroupBy
        XCTAssertEqual(lastGroupBy, "day")
    }

    // MARK: - Range picker triggers reload

    func test_preset_change_updates_from_date() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        let before = vm.fromDateString
        vm.selectedPreset = .sevenDays
        XCTAssertNotEqual(vm.fromDateString, before)
    }
}

// MARK: - StubReportsRepository actor mutators for tests

extension StubReportsRepository {
    func setRevenueResult(_ result: Result<[RevenuePoint], Error>) {
        revenueResult = result
    }
    func setTicketsResult(_ result: Result<[TicketStatusPoint], Error>) {
        ticketsResult = result
    }
    func setEmployeesResult(_ result: Result<[EmployeePerf], Error>) {
        employeesResult = result
    }
    func setInventoryResult(_ result: Result<[InventoryTurnoverRow], Error>) {
        inventoryResult = result
    }
}
