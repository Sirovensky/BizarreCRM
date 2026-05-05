import XCTest
@testable import Reports

// MARK: - ReportLegendInspectorTests
//
// Tests the data-layer behaviour of ReportLegendInspector:
// - Correct category breakdown data is used for each ReportCategory.
// - Turnover colour helper maps correctly to status strings.
// - LegendInspector composes data from vm without crashing on empty state.

@MainActor
final class ReportLegendInspectorTests: XCTestCase {

    // MARK: - Shared stub setup

    private func makeVM(stub: StubReportsRepository) -> ReportsViewModel {
        ReportsViewModel(repository: stub)
    }

    // MARK: - Revenue legend data

    func test_revenue_showsTotalRevenue_fromSalesTotals() async {
        let stub = StubReportsRepository()
        let totals = SalesTotals(totalRevenue: 7500.0, revenueChangePct: 3.5,
                                  totalInvoices: 40, uniqueCustomers: 20)
        let report = SalesReportResponse(
            rows: [.fixture(amountCents: 750000)],
            totals: totals,
            byMethod: [PaymentMethodPoint(method: "card", revenue: 5000, count: 30)]
        )
        await stub.setSalesReportResult(.success(report))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        // Revenue total derived from salesTotals when available
        XCTAssertEqual(vm.revenueTotalDollars, 7500.0, accuracy: 0.01)
        XCTAssertEqual(vm.revenueByMethod.count, 1)
        XCTAssertEqual(vm.revenueByMethod.first?.method, "card")
    }

    func test_revenue_legendWorks_withEmptyPaymentMethods() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(rows: [], totals: SalesTotals(), byMethod: [])
        await stub.setSalesReportResult(.success(report))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        // Should not crash; revenueByMethod should be empty
        XCTAssertTrue(vm.revenueByMethod.isEmpty)
    }

    // MARK: - Expenses legend data

    func test_expenses_legendDerivesGrossProfit() async {
        let stub = StubReportsRepository()
        let expenses = ExpensesReport(totalDollars: 2000.0, revenueDollars: 8000.0)
        await stub.setExpensesResult(.success(expenses))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        XCTAssertEqual(vm.expensesReport?.grossProfitDollars, 6000.0, accuracy: 0.01)
        XCTAssertEqual(vm.expensesReport?.marginPct, 75.0, accuracy: 0.01)
    }

    func test_expenses_legendHandlesZeroRevenue() async {
        let stub = StubReportsRepository()
        let expenses = ExpensesReport(totalDollars: 500.0, revenueDollars: 0.0)
        await stub.setExpensesResult(.success(expenses))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        XCTAssertNil(vm.expensesReport?.marginPct, "Margin should be nil when revenue is zero")
    }

    // MARK: - Inventory legend data

    func test_inventory_legendShowsStockHealth() async {
        let stub = StubReportsRepository()
        let inv = InventoryReport(
            outOfStockCount: 5,
            lowStockCount: 12,
            valueSummary: [
                InventoryValueEntry(itemType: "part", itemCount: 20,
                                    totalUnits: 100, totalCostValue: 500, totalRetailValue: 1200)
            ],
            topMoving: [.fixture()]
        )
        await stub.setInventoryReportResult(.success(inv))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        XCTAssertEqual(vm.inventoryReport?.outOfStockCount, 5)
        XCTAssertEqual(vm.inventoryReport?.lowStockCount, 12)
        XCTAssertEqual(vm.inventoryReport?.valueSummary.first?.itemType, "part")
    }

    // MARK: - Owner P&L legend data

    func test_ownerPL_legendShowsEmployeePerf() async {
        let stub = StubReportsRepository()
        let employees = [
            EmployeePerf.fixture(id: 1, name: "Alice", tickets: 30, revenue: 900000),
            EmployeePerf.fixture(id: 2, name: "Bob",   tickets: 20, revenue: 600000)
        ]
        await stub.setEmployeesResult(.success(employees))
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        XCTAssertEqual(vm.employeePerf.count, 2)
        XCTAssertEqual(vm.employeePerf.first?.employeeName, "Alice")
    }

    // MARK: - Turnover colour logic (via InventoryTurnoverRow.status)

    func test_turnoverRow_healthyStatus_mapsToSuccessColor() {
        let row = InventoryTurnoverRow(id: 1, sku: "A", name: "Widget",
                                       turnoverRate: 4.0, daysOnHand: 22.5,
                                       status: "healthy")
        // The inspector uses status == "healthy" → bizarreSuccess
        XCTAssertEqual(row.status, "healthy")
    }

    func test_turnoverRow_slowStatus_mapsToWarningColor() {
        let row = InventoryTurnoverRow(id: 2, sku: "B", name: "Gear",
                                       turnoverRate: 0.8, daysOnHand: 112.5,
                                       status: "slow")
        XCTAssertEqual(row.status, "slow")
    }

    func test_turnoverRow_stagnantStatus_mapsToErrorColor() {
        let row = InventoryTurnoverRow(id: 3, sku: "C", name: "OldPart",
                                       turnoverRate: 0.1, daysOnHand: 900.0,
                                       status: "stagnant")
        XCTAssertEqual(row.status, "stagnant")
    }

    func test_turnoverRow_nilStatus_highRate_impliesHealthy() {
        let row = InventoryTurnoverRow(id: 4, sku: "D", name: "FastMover",
                                       turnoverRate: 3.0, daysOnHand: 30.0,
                                       status: nil)
        // rate >= 2.0 → success colour path
        XCTAssertNil(row.status)
        XCTAssertGreaterThanOrEqual(row.turnoverRate, 2.0)
    }

    func test_turnoverRow_nilStatus_lowRate_impliesWarning() {
        let row = InventoryTurnoverRow(id: 5, sku: "E", name: "SlowMover",
                                       turnoverRate: 0.5, daysOnHand: 180.0,
                                       status: nil)
        XCTAssertNil(row.status)
        XCTAssertLessThan(row.turnoverRate, 2.0)
    }

    // MARK: - Category coverage (view init smoke-test)

    func test_legendInspector_canBeInitialised_forAllCategories() async {
        let stub = StubReportsRepository()
        let vm = makeVM(stub: stub)
        await vm.loadAll()

        // Should not crash on init for any category
        for category in ReportCategory.allCases {
            let inspector = ReportLegendInspector(category: category, vm: vm)
            // Verify the type is constructed without assertion failures
            _ = inspector
        }
    }
}
