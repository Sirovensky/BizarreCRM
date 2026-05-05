import XCTest
@testable import Reports

// MARK: - ReportsViewModelTests
// Tests that:
// - Range picker changes trigger correct endpoint parameters.
// - loadAll() populates all data fields from the wired endpoints.
// - Error path sets errorMessage without crashing.
// - New fields (expenses, inventory report) are populated.

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
        let report = SalesReportResponse(
            rows: [.fixture()],
            totals: SalesTotals(totalRevenue: 100.0, revenueChangePct: 5.5,
                                totalInvoices: 1, uniqueCustomers: 1),
            byMethod: []
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenue.count, 1)
    }

    func test_loadAll_populatesRevenueByMethod() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(
            rows: [],
            totals: SalesTotals(),
            byMethod: [PaymentMethodPoint(method: "cash", revenue: 500, count: 5)]
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenueByMethod.count, 1)
    }

    func test_loadAll_populatesSalesTotals() async {
        let stub = StubReportsRepository()
        let totals = SalesTotals(totalRevenue: 9999.0, revenueChangePct: -2.5,
                                  totalInvoices: 50, uniqueCustomers: 30)
        let report = SalesReportResponse(rows: [], totals: totals, byMethod: [])
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.salesTotals.totalRevenue, 9999.0, accuracy: 0.01)
        XCTAssertEqual(vm.salesTotals.revenueChangePct, -2.5)
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

    func test_loadAll_populatesInventoryReport() async {
        let stub = StubReportsRepository()
        let report = InventoryReport(
            outOfStockCount: 3,
            lowStockCount: 7,
            valueSummary: [InventoryValueEntry(itemType: "part", itemCount: 10,
                                               totalUnits: 50, totalCostValue: 1000,
                                               totalRetailValue: 2000)],
            topMoving: [.fixture()]
        )
        await stub.setInventoryReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.inventoryReport)
        XCTAssertEqual(vm.inventoryReport?.outOfStockCount, 3)
        XCTAssertEqual(vm.inventoryReport?.lowStockCount, 7)
        XCTAssertEqual(vm.inventoryReport?.topMoving.count, 1)
    }

    func test_loadAll_populatesExpensesReport() async {
        let stub = StubReportsRepository()
        let expenses = ExpensesReport(
            totalDollars: 1500.0,
            revenueDollars: 6000.0,
            dailyBreakdown: [.fixture()]
        )
        await stub.setExpensesResult(.success(expenses))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.expensesReport)
        XCTAssertEqual(vm.expensesReport?.totalDollars, 1500.0, accuracy: 0.01)
        XCTAssertEqual(vm.expensesReport?.revenueDollars, 6000.0, accuracy: 0.01)
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
        await stub.setSalesReportResult(.failure(RepoTestError.bang))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("Revenue") == true)
    }

    func test_loadAll_expensesError_setsErrorMessage() async {
        let stub = StubReportsRepository()
        await stub.setExpensesResult(.failure(RepoTestError.bang))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - CSAT stub silently suppressed

    func test_loadAll_csatEndpointMissing_doesNotSetErrorMessage() async {
        // CSAT endpoint not implemented — error should be silently swallowed
        let stub = StubReportsRepository()
        // csatResult defaults to .failure(endpointNotImplemented)
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        // errorMessage may be set for other reasons but should NOT say "CSAT"
        let msg = vm.errorMessage ?? ""
        XCTAssertFalse(msg.contains("CSAT"),
                       "CSAT endpointNotImplemented error should be suppressed, got: \(msg)")
    }

    // MARK: - Hero tile computed

    func test_revenueTotalCents_sumsAllPoints() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(
            rows: [
                RevenuePoint.fixture(id: 1, amountCents: 5000),
                RevenuePoint.fixture(id: 2, date: "2024-01-02", amountCents: 3000)
            ],
            totals: SalesTotals(totalRevenue: 80.0),
            byMethod: []
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenueTotalCents, 8000)
    }

    func test_revenueTotalDollars_prefersSalesTotals() async {
        let stub = StubReportsRepository()
        // totals.totalRevenue overrides the sum of point cents
        let report = SalesReportResponse(
            rows: [RevenuePoint.fixture(id: 1, amountCents: 1000)],
            totals: SalesTotals(totalRevenue: 9999.0),
            byMethod: []
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenueTotalDollars, 9999.0, accuracy: 0.01)
    }

    func test_revenueTotalDollars_fallsBackToPointSum_whenTotalsZero() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(
            rows: [RevenuePoint.fixture(id: 1, amountCents: 5000)],
            totals: SalesTotals(totalRevenue: 0),
            byMethod: []
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.revenueTotalDollars, 50.0, accuracy: 0.001)
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
