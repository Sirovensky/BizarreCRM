import XCTest
@testable import Reports

final class FinancialExportServiceTests: XCTestCase {

    // MARK: - exportCSV

    func test_exportCSV_containsPnLSection() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "This Month")
        XCTAssertTrue(csv.contains("P&L Summary"))
        XCTAssertTrue(csv.contains("Revenue"))
        XCTAssertTrue(csv.contains("Net Income"))
    }

    func test_exportCSV_containsCashFlowSection() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "This Month")
        XCTAssertTrue(csv.contains("Cash Flow"))
    }

    func test_exportCSV_containsAgedReceivablesSection() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "Q1")
        XCTAssertTrue(csv.contains("Aged Receivables"))
        XCTAssertTrue(csv.contains("0-30"))
    }

    func test_exportCSV_containsTopCustomersSection() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "Test")
        XCTAssertTrue(csv.contains("Top Customers"))
    }

    func test_exportCSV_containsTopSkusSection() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "Test")
        XCTAssertTrue(csv.contains("Top SKUs"))
    }

    func test_exportCSV_isNotEmpty() {
        let data = makeData()
        let csv = FinancialExportService.exportCSV(data: data, period: "Test")
        XCTAssertFalse(csv.isEmpty)
    }

    // MARK: - exportTaxYearCSV

    func test_exportTaxYearCSV_containsYearHeader() {
        let taxData = TaxYearData(
            year: 2024,
            revenueByMonth: [("January", 10000), ("February", 20000)],
            salesTaxCollectedCents: 5000,
            expensesByCategory: [("Rent", 15000)],
            totalCOGSCents: 8000
        )
        let csv = FinancialExportService.exportTaxYearCSV(data: taxData)
        XCTAssertTrue(csv.contains("Tax Year 2024"))
        XCTAssertTrue(csv.contains("January"))
        XCTAssertTrue(csv.contains("Sales Tax Collected"))
    }

    func test_exportTaxYearCSV_expensesCategoryIncluded() {
        let taxData = TaxYearData(
            year: 2025,
            revenueByMonth: [],
            salesTaxCollectedCents: 0,
            expensesByCategory: [("Utilities", 3000)],
            totalCOGSCents: 0
        )
        let csv = FinancialExportService.exportTaxYearCSV(data: taxData)
        XCTAssertTrue(csv.contains("Utilities"))
    }

    // MARK: - Helpers

    private func makeData() -> FinancialDashboardData {
        let pnl = PnLSnapshot(revenueCents: 100000, cogsCents: 40000, expensesCents: 10000)
        let cashFlow = [
            CashFlowPoint(id: "2025-01", date: Date(), inflowCents: 50000, outflowCents: 20000)
        ]
        let aging = AgedReceivablesSnapshot(
            current:    AgedReceivablesBucket(label: "0-30",  totalCents: 5000, invoiceCount: 2),
            thirtyPlus: AgedReceivablesBucket(label: "31-60", totalCents: 1000, invoiceCount: 1),
            sixtyPlus:  AgedReceivablesBucket(label: "61-90", totalCents: 0,    invoiceCount: 0),
            ninetyPlus: AgedReceivablesBucket(label: "90+",   totalCents: 500,  invoiceCount: 1)
        )
        let customers = [TopCustomer(id: "c1", name: "Alice", revenueCents: 30000)]
        let skus = [TopSkuByMargin(id: "s1", sku: "WD-001", name: "Widget", marginCents: 5000, marginPct: 0.5)]
        return FinancialDashboardData(
            pnl: pnl,
            cashFlow: cashFlow,
            agedReceivables: aging,
            topCustomers: customers,
            topSkus: skus
        )
    }
}
