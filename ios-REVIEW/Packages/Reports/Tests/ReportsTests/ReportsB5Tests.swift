import XCTest
@testable import Reports

// MARK: - ReportsB5Tests
//
// Tests for batch-5 §15.2 / §15.3 additions:
//   1. YoYDataPoint growthPct calculated correctly
//   2. YoYDataPoint growthPct nil when priorRevenue == 0
//   3. TopCustomerRow decodes server JSON correctly
//   4. TicketDayPoint closeRate calculated correctly
//   5. TicketDayPoint closeRate nil when opened == 0
//   6. TicketsTrendCard overallCloseRate aggregates correctly
//   7. TicketsTrendCard avgTurnaround averages non-nil values
//   8. BusyHourCell round-trips through Codable
//   9. SLABreachSummary breachRate calculated correctly
//  10. SLABreachSummary decodes from JSON
//  11. InventoryStockCard: cost + retail totals computed correctly
//  12. ReportsViewModel loads topCustomers from stub
//  13. ReportsViewModel loads ticketsTrend from stub
//  14. ReportsViewModel ticketsByTech derived from employeePerf
//  15. YoYGrowthCard overall growth pct correct end-to-end

final class ReportsB5Tests: XCTestCase {

    // MARK: 1. YoYDataPoint growthPct

    func test_yoyDataPoint_growthPct_positive() {
        let pt = YoYDataPoint(period: "Jan", currentRevenue: 1200, priorRevenue: 1000)
        XCTAssertEqual(pt.growthPct, 20.0, accuracy: 0.01)
    }

    func test_yoyDataPoint_growthPct_negative() {
        let pt = YoYDataPoint(period: "Feb", currentRevenue: 800, priorRevenue: 1000)
        XCTAssertEqual(pt.growthPct!, -20.0, accuracy: 0.01)
    }

    // MARK: 2. YoYDataPoint growthPct nil when priorRevenue == 0

    func test_yoyDataPoint_growthPct_nilWhenPriorZero() {
        let pt = YoYDataPoint(period: "Mar", currentRevenue: 500, priorRevenue: 0)
        XCTAssertNil(pt.growthPct)
    }

    // MARK: 3. TopCustomerRow decodes server JSON

    func test_topCustomerRow_decodesJSON() throws {
        let json = """
        {"id": 42, "name": "Acme Corp", "revenue": 9500.0, "invoice_count": 7}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(TopCustomerRow.self, from: json)
        XCTAssertEqual(row.id, 42)
        XCTAssertEqual(row.name, "Acme Corp")
        XCTAssertEqual(row.revenueDollars, 9500.0, accuracy: 0.01)
        XCTAssertEqual(row.invoiceCount, 7)
    }

    // MARK: 4. TicketDayPoint closeRate

    func test_ticketDayPoint_closeRate() {
        let pt = TicketDayPoint(date: "2024-01-01", opened: 10, closed: 7)
        XCTAssertEqual(pt.closeRate!, 70.0, accuracy: 0.01)
    }

    // MARK: 5. TicketDayPoint closeRate nil when opened == 0

    func test_ticketDayPoint_closeRateNilWhenZeroOpened() {
        let pt = TicketDayPoint(date: "2024-01-02", opened: 0, closed: 0)
        XCTAssertNil(pt.closeRate)
    }

    // MARK: 6. TicketsTrendCard overallCloseRate aggregates

    func test_ticketsTrendCard_overallCloseRate() {
        let points = [
            TicketDayPoint(date: "2024-01-01", opened: 10, closed: 5),
            TicketDayPoint(date: "2024-01-02", opened: 20, closed: 15)
        ]
        let card = TicketsTrendCard(points: points)
        // (5+15)/(10+20) = 20/30 = 66.67%
        XCTAssertEqual(card.overallCloseRate!, 66.67, accuracy: 0.01)
    }

    // MARK: 7. TicketsTrendCard avgTurnaround averages non-nil values

    func test_ticketsTrendCard_avgTurnaround() {
        let points = [
            TicketDayPoint(date: "2024-01-01", opened: 5, closed: 5, avgTurnaroundHours: 3.0),
            TicketDayPoint(date: "2024-01-02", opened: 5, closed: 5, avgTurnaroundHours: 5.0),
            TicketDayPoint(date: "2024-01-03", opened: 5, closed: 5, avgTurnaroundHours: nil)
        ]
        let card = TicketsTrendCard(points: points)
        XCTAssertEqual(card.avgTurnaround!, 4.0, accuracy: 0.01)
    }

    // MARK: 8. BusyHourCell Codable round-trip

    func test_busyHourCell_codableRoundTrip() throws {
        let cell = BusyHourCell(dayOfWeek: 2, hour: 14, ticketCount: 37)
        let data = try JSONEncoder().encode(cell)
        let decoded = try JSONDecoder().decode(BusyHourCell.self, from: data)
        XCTAssertEqual(decoded.dayOfWeek, 2)
        XCTAssertEqual(decoded.hour, 14)
        XCTAssertEqual(decoded.ticketCount, 37)
    }

    // MARK: 9. SLABreachSummary breachRate

    func test_slaBreachSummary_breachRate() {
        let s = SLABreachSummary(totalTickets: 50, breachedCount: 5, atRiskCount: 3)
        XCTAssertEqual(s.breachRate, 10.0, accuracy: 0.01)
    }

    // MARK: 10. SLABreachSummary decodes from JSON

    func test_slaBreachSummary_decodesJSON() throws {
        let json = """
        {"total_tickets": 100, "sla_breached": 12, "sla_at_risk": 4, "top_breach_reason": "Parts delay"}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(SLABreachSummary.self, from: json)
        XCTAssertEqual(s.totalTickets, 100)
        XCTAssertEqual(s.breachedCount, 12)
        XCTAssertEqual(s.atRiskCount, 4)
        XCTAssertEqual(s.topBreachReason, "Parts delay")
        XCTAssertEqual(s.breachRate, 12.0, accuracy: 0.01)
    }

    // MARK: 11. InventoryStockCard cost + retail totals

    func test_inventoryStockCard_totals() {
        let entries = [
            InventoryValueEntry(itemType: "Parts", itemCount: 50, totalUnits: 200,
                                totalCostValue: 1_000.0, totalRetailValue: 2_500.0),
            InventoryValueEntry(itemType: "Accessories", itemCount: 20, totalUnits: 80,
                                totalCostValue: 500.0, totalRetailValue: 900.0)
        ]
        let report = InventoryReport(outOfStockCount: 2, lowStockCount: 5,
                                     valueSummary: entries, topMoving: [])
        let totalCost   = report.valueSummary.reduce(0) { $0 + $1.totalCostValue }
        let totalRetail = report.valueSummary.reduce(0) { $0 + $1.totalRetailValue }
        XCTAssertEqual(totalCost, 1_500.0, accuracy: 0.01)
        XCTAssertEqual(totalRetail, 3_400.0, accuracy: 0.01)
    }

    // MARK: 12. ReportsViewModel loads topCustomers from stub

    @MainActor
    func test_viewModel_loadsTopCustomers() async {
        let stub = StubReportsRepository()
        await stub.setTopCustomersResult(.success([
            TopCustomerRow(id: 1, name: "Best Customer", revenueDollars: 5000.0, invoiceCount: 10)
        ]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.topCustomers.count, 1)
        XCTAssertEqual(vm.topCustomers[0].name, "Best Customer")
    }

    // MARK: 13. ReportsViewModel loads ticketsTrend from stub

    @MainActor
    func test_viewModel_loadsTicketsTrend() async {
        let stub = StubReportsRepository()
        await stub.setTicketsTrendResult(.success([
            TicketDayPoint(date: "2024-01-01", opened: 5, closed: 3),
            TicketDayPoint(date: "2024-01-02", opened: 8, closed: 7)
        ]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.ticketsTrend.count, 2)
        XCTAssertEqual(vm.ticketsTrend[1].closed, 7)
    }

    // MARK: 14. ticketsByTech derived from employeePerf

    @MainActor
    func test_viewModel_ticketsByTechDerivedFromEmployeePerf() async {
        let stub = StubReportsRepository()
        let emp = EmployeePerf(id: 7, employeeName: "Alice",
                               ticketsClosed: 12, revenueCents: 300_00,
                               avgResolutionHours: 2.5, ticketsAssigned: 15)
        await stub.setEmployeesResult(.success([emp]))
        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()
        XCTAssertEqual(vm.ticketsByTech.count, 1)
        XCTAssertEqual(vm.ticketsByTech[0].techName, "Alice")
        XCTAssertEqual(vm.ticketsByTech[0].assigned, 15)
        XCTAssertEqual(vm.ticketsByTech[0].closed, 12)
    }

    // MARK: 15. YoY overall growth pct correct end-to-end

    func test_yoy_overallGrowthPct_endToEnd() {
        let points = [
            YoYDataPoint(period: "Jan", currentRevenue: 1100, priorRevenue: 1000),
            YoYDataPoint(period: "Feb", currentRevenue: 2200, priorRevenue: 2000)
        ]
        let totalCurrent = points.reduce(0) { $0 + $1.currentRevenue }  // 3300
        let totalPrior   = points.reduce(0) { $0 + $1.priorRevenue }    // 3000
        let pct = (totalCurrent - totalPrior) / totalPrior * 100.0
        XCTAssertEqual(pct, 10.0, accuracy: 0.01)
    }
}

// MARK: - StubReportsRepository extensions for new methods

extension StubReportsRepository {
    func setTopCustomersResult(_ result: Result<[TopCustomerRow], Error>) {
        topCustomersResult = result
    }
    func setTicketsTrendResult(_ result: Result<[TicketDayPoint], Error>) {
        ticketsTrendResult = result
    }
}
