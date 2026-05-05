import XCTest
@testable import Reports

// MARK: - ExpensesReportTests
// Tests for ExpensesReport model calculations and DailySalePoint decoding.

final class ExpensesReportTests: XCTestCase {

    // MARK: - ExpensesReport computed properties

    func test_grossProfit_isRevenueMinus_expenses() {
        let r = ExpensesReport(totalDollars: 400.0, revenueDollars: 1000.0)
        XCTAssertEqual(r.grossProfitDollars, 600.0, accuracy: 0.001)
    }

    func test_marginPct_calculatedCorrectly() {
        let r = ExpensesReport(totalDollars: 400.0, revenueDollars: 1000.0)
        let margin = r.marginPct
        XCTAssertNotNil(margin)
        XCTAssertEqual(margin!, 60.0, accuracy: 0.001)
    }

    func test_marginPct_nilWhenRevenueZero() {
        let r = ExpensesReport(totalDollars: 100.0, revenueDollars: 0.0)
        XCTAssertNil(r.marginPct)
    }

    func test_grossProfit_canBeNegative() {
        let r = ExpensesReport(totalDollars: 1500.0, revenueDollars: 1000.0)
        XCTAssertLessThan(r.grossProfitDollars, 0)
    }

    // MARK: - ExpenseDayPoint

    func test_expenseDayPoint_netProfit() {
        let pt = ExpenseDayPoint(date: "2024-01-01", revenue: 800.0, cogs: 300.0)
        XCTAssertEqual(pt.netProfit, 500.0, accuracy: 0.001)
    }

    func test_expenseDayPoint_id_equalsDate() {
        let pt = ExpenseDayPoint(date: "2024-02-15", revenue: 0, cogs: 0)
        XCTAssertEqual(pt.id, "2024-02-15")
    }

    // MARK: - DashboardKpisResponse decoding

    func test_dashboardKpisResponse_decodesExpenses() throws {
        let json = """
        {
            "total_sales": 5000.0,
            "expenses": 1200.5,
            "cogs": 800.0,
            "daily_sales": [
                {"date": "2024-01-01", "sale": 500.0, "cogs": 200.0, "net_profit": 300.0, "margin": 60.0}
            ]
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DashboardKpisResponse.self, from: json)
        XCTAssertEqual(decoded.expenses, 1200.5, accuracy: 0.001)
        XCTAssertEqual(decoded.totalSales, 5000.0, accuracy: 0.001)
        XCTAssertEqual(decoded.dailySales.count, 1)
        XCTAssertEqual(decoded.dailySales[0].sale, 500.0, accuracy: 0.001)
        XCTAssertEqual(decoded.dailySales[0].marginPct, 60.0)
    }

    func test_dashboardKpisResponse_missingFields_defaultsToZero() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DashboardKpisResponse.self, from: json)
        XCTAssertEqual(decoded.expenses, 0)
        XCTAssertEqual(decoded.totalSales, 0)
        XCTAssertTrue(decoded.dailySales.isEmpty)
    }

    // MARK: - SalesReportResponse decoding

    func test_salesReportResponse_decodesRows() throws {
        let json = """
        {
            "rows": [
                {"period": "2024-01-01", "revenue": 500.0, "invoices": 5, "unique_customers": 3}
            ],
            "totals": {
                "total_revenue": 500.0,
                "revenue_change_pct": 10.5,
                "total_invoices": 5,
                "unique_customers": 3
            },
            "byMethod": []
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SalesReportResponse.self, from: json)
        XCTAssertEqual(decoded.rows.count, 1)
        XCTAssertEqual(decoded.rows[0].date, "2024-01-01")
        XCTAssertEqual(decoded.rows[0].amountCents, 50000) // $500 → 50000 cents
        XCTAssertEqual(decoded.totals.totalRevenue, 500.0, accuracy: 0.001)
        XCTAssertEqual(decoded.totals.revenueChangePct, 10.5)
    }

    func test_revenuePoint_decodes_period_shape() throws {
        let json = """
        {"period": "2024-03", "revenue": 1234.56, "invoices": 12, "unique_customers": 8}
        """.data(using: .utf8)!
        let pt = try JSONDecoder().decode(RevenuePoint.self, from: json)
        XCTAssertEqual(pt.date, "2024-03")
        XCTAssertEqual(pt.amountCents, 123456) // $1234.56 → 123456 cents
        XCTAssertEqual(pt.saleCount, 12)
    }

    func test_revenuePoint_decodes_legacy_shape() throws {
        let json = """
        {"id": 7, "date": "2024-01-15", "amount_cents": 9999, "sale_count": 3}
        """.data(using: .utf8)!
        let pt = try JSONDecoder().decode(RevenuePoint.self, from: json)
        XCTAssertEqual(pt.id, 7)
        XCTAssertEqual(pt.date, "2024-01-15")
        XCTAssertEqual(pt.amountCents, 9999)
        XCTAssertEqual(pt.saleCount, 3)
    }
}
