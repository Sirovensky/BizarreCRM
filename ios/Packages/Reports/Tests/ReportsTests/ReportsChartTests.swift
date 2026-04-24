import XCTest
@testable import Reports
import Networking

// MARK: - ReportsChartTests
//
// Tests for §15:
//   1. ReportsViewModel parses server response correctly
//   2. ReportsViewModel handles empty arrays (empty state)
//   3. ReportsViewModel handles a simulated 500 error
//   4. Granularity toggle passes correct group_by
//   5. Date-range preset changes propagate correctly
//   6. RevenueReportPayload decodes server JSON correctly
//   7. InventoryReportPayload decodes server JSON correctly
//   8. DashboardKpisPayload decodes server JSON correctly

// MARK: - Helpers

private enum ServerError: Error, LocalizedError {
    case internalServerError
    public var errorDescription: String? { "Internal Server Error (500)" }
}

// MARK: - ReportsViewModel — server response parsing

@MainActor
final class ReportsViewModelChartTests: XCTestCase {

    // MARK: Revenue

    func test_parsesRevenueTotals_fromServerResponse() async {
        let stub = StubReportsRepository()
        let totals = SalesTotals(
            totalRevenue: 12_345.67,
            revenueChangePct: 8.3,
            totalInvoices: 42,
            uniqueCustomers: 19
        )
        let report = SalesReportResponse(
            rows: [
                RevenuePoint.fixture(id: 1, amountCents: 100_00, saleCount: 3),
                RevenuePoint.fixture(id: 2, date: "2024-02-01", amountCents: 200_00, saleCount: 7)
            ],
            totals: totals,
            byMethod: [PaymentMethodPoint(method: "card", revenue: 9000, count: 30)]
        )
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.revenue.count, 2)
        XCTAssertEqual(vm.salesTotals.totalRevenue, 12_345.67, accuracy: 0.01)
        XCTAssertEqual(vm.salesTotals.revenueChangePct, 8.3)
        XCTAssertEqual(vm.salesTotals.totalInvoices, 42)
        XCTAssertEqual(vm.revenueByMethod.count, 1)
        XCTAssertEqual(vm.revenueByMethod.first?.method, "card")
    }

    func test_parsesInventoryReport_fromServerResponse() async {
        let stub = StubReportsRepository()
        let report = InventoryReport(
            outOfStockCount: 5,
            lowStockCount: 12,
            valueSummary: [
                InventoryValueEntry(itemType: "part", itemCount: 100, totalUnits: 500,
                                    totalCostValue: 2500.0, totalRetailValue: 5000.0)
            ],
            topMoving: [
                InventoryMovementItem.fixture(name: "Screen", sku: "SCR01", usedQty: 25, inStock: 8)
            ]
        )
        await stub.setInventoryReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.inventoryReport?.outOfStockCount, 5)
        XCTAssertEqual(vm.inventoryReport?.lowStockCount, 12)
        XCTAssertEqual(vm.inventoryReport?.valueSummary.count, 1)
        XCTAssertEqual(vm.inventoryReport?.valueSummary.first?.itemType, "part")
        XCTAssertEqual(vm.inventoryReport?.topMoving.count, 1)
        XCTAssertEqual(vm.inventoryReport?.topMoving.first?.usedQty, 25)
    }

    func test_parsesExpensesReport_fromServerResponse() async {
        let stub = StubReportsRepository()
        let expenses = ExpensesReport(
            totalDollars: 3_200.50,
            revenueDollars: 11_000.00,
            dailyBreakdown: [
                ExpenseDayPoint.fixture(date: "2024-03-01", revenue: 800.0, cogs: 300.0),
                ExpenseDayPoint.fixture(date: "2024-03-02", revenue: 1000.0, cogs: 400.0)
            ]
        )
        await stub.setExpensesResult(.success(expenses))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertEqual(vm.expensesReport?.totalDollars, 3_200.50, accuracy: 0.01)
        XCTAssertEqual(vm.expensesReport?.revenueDollars, 11_000.0, accuracy: 0.01)
        XCTAssertEqual(vm.expensesReport?.dailyBreakdown.count, 2)
        let margin = vm.expensesReport?.marginPct
        XCTAssertNotNil(margin)
        XCTAssertEqual(margin ?? 0, (11_000 - 3_200.50) / 11_000 * 100, accuracy: 0.01)
    }

    // MARK: Empty state

    func test_emptyRevenue_doesNotCrash_andSetsZeroTotal() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(rows: [], totals: SalesTotals(totalRevenue: 0), byMethod: [])
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertTrue(vm.revenue.isEmpty)
        XCTAssertEqual(vm.revenueTotalCents, 0)
        XCTAssertEqual(vm.revenueTotalDollars, 0, accuracy: 0.001)
        XCTAssertNil(vm.errorMessage, "No error expected for empty data")
    }

    func test_emptyInventory_doesNotCrash() async {
        let stub = StubReportsRepository()
        let report = InventoryReport(outOfStockCount: 0, lowStockCount: 0,
                                     valueSummary: [], topMoving: [])
        await stub.setInventoryReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertNotNil(vm.inventoryReport)
        XCTAssertEqual(vm.inventoryReport?.topMoving.count, 0)
        XCTAssertNil(vm.errorMessage, "No error expected for empty inventory")
    }

    func test_emptyExpenses_doesNotCrash() async {
        let stub = StubReportsRepository()
        let expenses = ExpensesReport(totalDollars: 0, revenueDollars: 0, dailyBreakdown: [])
        await stub.setExpensesResult(.success(expenses))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertNotNil(vm.expensesReport)
        XCTAssertEqual(vm.expensesReport?.dailyBreakdown.count, 0)
        XCTAssertNil(vm.expensesReport?.marginPct, "Margin should be nil when revenue is zero")
    }

    func test_emptyByMethod_doesNotCrash() async {
        let stub = StubReportsRepository()
        let report = SalesReportResponse(rows: [], totals: SalesTotals(), byMethod: [])
        await stub.setSalesReportResult(.success(report))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertTrue(vm.revenueByMethod.isEmpty)
    }

    // MARK: 500 / server error

    func test_revenue500Error_setsErrorMessage_doesNotCrash() async {
        let stub = StubReportsRepository()
        await stub.setSalesReportResult(.failure(ServerError.internalServerError))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertNotNil(vm.errorMessage, "Error message should be set after 500")
        XCTAssertTrue(vm.errorMessage?.contains("Revenue") == true,
                      "Error message should mention Revenue, got: \(vm.errorMessage ?? "")")
        XCTAssertTrue(vm.revenue.isEmpty, "Revenue should remain empty after error")
        XCTAssertFalse(vm.isLoading, "isLoading must be false after completion")
    }

    func test_inventory500Error_setsErrorMessage_doesNotCrash() async {
        let stub = StubReportsRepository()
        await stub.setInventoryReportResult(.failure(ServerError.internalServerError))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("Inventory") == true,
                      "Error should mention Inventory, got: \(vm.errorMessage ?? "")")
        XCTAssertNil(vm.inventoryReport, "inventoryReport should remain nil after error")
    }

    func test_expenses500Error_setsErrorMessage_doesNotCrash() async {
        let stub = StubReportsRepository()
        await stub.setExpensesResult(.failure(ServerError.internalServerError))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.expensesReport, "expensesReport should remain nil after error")
        XCTAssertFalse(vm.isLoading)
    }

    func test_multipleErrors_lastWins_stillCompletes() async {
        // When both revenue and expenses fail, vm still completes (isLoading = false)
        let stub = StubReportsRepository()
        await stub.setSalesReportResult(.failure(ServerError.internalServerError))
        await stub.setExpensesResult(.failure(ServerError.internalServerError))
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.lastSyncedAt)
    }

    // MARK: Granularity toggle

    func test_granularityDefault_isDay() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        XCTAssertEqual(vm.granularity, .day)
    }

    func test_granularityWeek_passesWeekToRepository() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.granularity = .week

        await vm.loadAll()

        let lastGroupBy = await stub.revenueLastGroupBy
        XCTAssertEqual(lastGroupBy, "week")
    }

    func test_granularityMonth_passesMonthToRepository() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.granularity = .month

        await vm.loadAll()

        let lastGroupBy = await stub.revenueLastGroupBy
        XCTAssertEqual(lastGroupBy, "month")
    }

    func test_granularityDay_passedOnDefaultLoad() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        await vm.loadAll()

        let lastGroupBy = await stub.revenueLastGroupBy
        XCTAssertEqual(lastGroupBy, "day")
    }

    // MARK: Date-range + granularity interaction

    func test_sevenDayPreset_withWeekGranularity() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        vm.selectedPreset = .sevenDays
        vm.granularity = .week

        await vm.loadAll()

        let lastGroupBy = await stub.revenueLastGroupBy
        XCTAssertEqual(lastGroupBy, "week")

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]
        let fromDate = isoFmt.date(from: vm.fromDateString)!
        let diff = Date().timeIntervalSince(fromDate)
        XCTAssertEqual(diff / 86400, 7.0, accuracy: 1.0)
    }
}

// MARK: - RevenueReportPayload JSON decoding tests

final class RevenueReportPayloadDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    func test_decodesFullPayload_fromServerJSON() throws {
        let json = """
        {
            "rows": [
                { "period": "2024-01-01", "revenue": 1500.50, "invoices": 10, "unique_customers": 5 },
                { "period": "2024-01-02", "revenue": 2300.00, "invoices": 15, "unique_customers": 8 }
            ],
            "totals": {
                "total_revenue": 3800.50,
                "revenue_change_pct": 12.5,
                "total_invoices": 25,
                "unique_customers": 13
            },
            "byMethod": [
                { "method": "card", "revenue": 2800.0, "count": 18 },
                { "method": "cash", "revenue": 1000.5, "count": 7 }
            ]
        }
        """.data(using: .utf8)!

        let payload = try decoder.decode(RevenueReportPayload.self, from: json)

        XCTAssertEqual(payload.rows.count, 2)
        XCTAssertEqual(payload.rows[0].period, "2024-01-01")
        XCTAssertEqual(payload.rows[0].revenue, 1500.50, accuracy: 0.01)
        XCTAssertEqual(payload.rows[0].invoices, 10)
        XCTAssertEqual(payload.rows[0].revenueCents, 150_050)
        XCTAssertEqual(payload.totals.totalRevenue, 3800.50, accuracy: 0.01)
        XCTAssertEqual(payload.totals.revenueChangePct, 12.5)
        XCTAssertEqual(payload.totals.totalInvoices, 25)
        XCTAssertEqual(payload.byMethod.count, 2)
        XCTAssertEqual(payload.byMethod[0].method, "card")
    }

    func test_decodesEmptyRows_gracefully() throws {
        let json = """
        {
            "rows": [],
            "totals": { "total_revenue": 0.0, "total_invoices": 0, "unique_customers": 0 },
            "byMethod": []
        }
        """.data(using: .utf8)!

        let payload = try decoder.decode(RevenueReportPayload.self, from: json)

        XCTAssertTrue(payload.rows.isEmpty)
        XCTAssertEqual(payload.totals.totalRevenue, 0)
        XCTAssertNil(payload.totals.revenueChangePct)
    }

    func test_decodesMissingOptionals_withoutCrash() throws {
        // Minimal valid response — only required fields
        let json = """
        {
            "rows": [{ "period": "2024-03-15", "revenue": 500 }],
            "totals": {},
            "byMethod": []
        }
        """.data(using: .utf8)!

        let payload = try decoder.decode(RevenueReportPayload.self, from: json)

        XCTAssertEqual(payload.rows.count, 1)
        XCTAssertEqual(payload.rows[0].invoices, 0)
        XCTAssertEqual(payload.rows[0].uniqueCustomers, 0)
        XCTAssertEqual(payload.totals.totalRevenue, 0)
    }
}

// MARK: - InventoryReportPayload JSON decoding tests

final class InventoryReportPayloadDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    func test_decodesFullPayload_fromServerJSON() throws {
        let json = """
        {
            "lowStock": [
                { "id": 1, "name": "LCD Screen", "sku": "LCD001", "in_stock": 2, "reorder_level": 5 }
            ],
            "valueSummary": [
                {
                    "item_type": "part",
                    "item_count": 120,
                    "total_units": 600,
                    "total_cost_value": 3000.0,
                    "total_retail_value": 6000.0
                }
            ],
            "outOfStock": 3,
            "topMoving": [
                { "id": 5, "name": "Battery", "sku": "BAT01", "in_stock": 10, "used_qty": 45 }
            ]
        }
        """.data(using: .utf8)!

        let payload = try decoder.decode(InventoryReportPayload.self, from: json)

        XCTAssertEqual(payload.outOfStock, 3)
        XCTAssertEqual(payload.lowStock.count, 1)
        XCTAssertEqual(payload.lowStock[0].name, "LCD Screen")
        XCTAssertEqual(payload.lowStock[0].inStock, 2)
        XCTAssertEqual(payload.valueSummary.count, 1)
        XCTAssertEqual(payload.valueSummary[0].itemType, "part")
        XCTAssertEqual(payload.valueSummary[0].totalRetailValue, 6000.0, accuracy: 0.01)
        XCTAssertEqual(payload.topMoving.count, 1)
        XCTAssertEqual(payload.topMoving[0].usedQty, 45)
    }

    func test_decodesAllEmpty_gracefully() throws {
        let json = """
        { "lowStock": [], "valueSummary": [], "outOfStock": 0, "topMoving": [] }
        """.data(using: .utf8)!

        let payload = try decoder.decode(InventoryReportPayload.self, from: json)

        XCTAssertEqual(payload.outOfStock, 0)
        XCTAssertTrue(payload.lowStock.isEmpty)
        XCTAssertTrue(payload.valueSummary.isEmpty)
        XCTAssertTrue(payload.topMoving.isEmpty)
    }
}

// MARK: - DashboardKpisPayload JSON decoding tests

final class DashboardKpisPayloadDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    func test_decodesFullPayload_fromServerJSON() throws {
        let json = """
        {
            "total_sales": 8500.0,
            "expenses": 2100.0,
            "cogs": 1200.0,
            "daily_sales": [
                { "date": "2024-04-01", "sale": 1200.0, "cogs": 400.0, "net_profit": 800.0 },
                { "date": "2024-04-02", "sale": 1500.0, "cogs": 500.0, "net_profit": 1000.0, "margin": 66.7 }
            ]
        }
        """.data(using: .utf8)!

        let payload = try decoder.decode(DashboardKpisPayload.self, from: json)

        XCTAssertEqual(payload.totalSales, 8500.0, accuracy: 0.01)
        XCTAssertEqual(payload.expenses, 2100.0, accuracy: 0.01)
        XCTAssertEqual(payload.cogs, 1200.0, accuracy: 0.01)
        XCTAssertEqual(payload.dailySales.count, 2)
        XCTAssertEqual(payload.dailySales[0].date, "2024-04-01")
        XCTAssertEqual(payload.dailySales[0].sale, 1200.0, accuracy: 0.01)
        XCTAssertNil(payload.dailySales[0].marginPct)
        XCTAssertEqual(payload.dailySales[1].marginPct, 66.7, accuracy: 0.01)
    }

    func test_decodesEmptyDailySales_gracefully() throws {
        let json = """
        { "total_sales": 0, "expenses": 0, "cogs": 0, "daily_sales": [] }
        """.data(using: .utf8)!

        let payload = try decoder.decode(DashboardKpisPayload.self, from: json)

        XCTAssertTrue(payload.dailySales.isEmpty)
        XCTAssertEqual(payload.totalSales, 0)
    }
}

// MARK: - ReportGranularity tests

final class ReportGranularityTests: XCTestCase {

    func test_rawValues_matchServerExpectedValues() {
        XCTAssertEqual(ReportGranularity.day.rawValue,   "day")
        XCTAssertEqual(ReportGranularity.week.rawValue,  "week")
        XCTAssertEqual(ReportGranularity.month.rawValue, "month")
    }

    func test_displayLabels_areNonEmpty() {
        for g in ReportGranularity.allCases {
            XCTAssertFalse(g.displayLabel.isEmpty)
        }
    }

    func test_allCases_hasThreeOptions() {
        XCTAssertEqual(ReportGranularity.allCases.count, 3)
    }

    func test_identifiable_idMatchesRawValue() {
        for g in ReportGranularity.allCases {
            XCTAssertEqual(g.id, g.rawValue)
        }
    }
}

// MARK: - ExpensesReport computed property tests

final class ExpensesReportComputedTests: XCTestCase {

    func test_grossProfit_isRevenueMinusExpenses() {
        let r = ExpensesReport(totalDollars: 400, revenueDollars: 1000)
        XCTAssertEqual(r.grossProfitDollars, 600, accuracy: 0.01)
    }

    func test_marginPct_computedCorrectly() {
        let r = ExpensesReport(totalDollars: 300, revenueDollars: 1000)
        XCTAssertEqual(r.marginPct ?? 0, 70.0, accuracy: 0.01)
    }

    func test_marginPct_nilWhenRevenueZero() {
        let r = ExpensesReport(totalDollars: 100, revenueDollars: 0)
        XCTAssertNil(r.marginPct)
    }

    func test_negativeProfitReported_whenExpensesExceedRevenue() {
        let r = ExpensesReport(totalDollars: 5000, revenueDollars: 3000)
        XCTAssertLessThan(r.grossProfitDollars, 0)
        XCTAssertNotNil(r.marginPct)
        XCTAssertLessThan(r.marginPct ?? 0, 0)
    }
}
