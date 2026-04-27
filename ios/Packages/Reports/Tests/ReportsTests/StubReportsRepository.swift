import Foundation
@testable import Reports

// MARK: - StubReportsRepository

actor StubReportsRepository: ReportsRepository {

    // MARK: - Canned results

    var revenueResult: Result<[RevenuePoint], Error> = .success([])
    var salesReportResult: Result<SalesReportResponse, Error> = .success(SalesReportResponse())
    var ticketsResult: Result<[TicketStatusPoint], Error> = .success([])
    var ticketsReportResult: Result<TicketsReportResponse, Error> = .success(
        TicketsReportResponse(
            byStatus: [],
            summary: TicketsSummary(totalCreated: 0, totalClosed: 0, avgTicketValue: 50.0)
        )
    )
    var avgTicketResult: Result<AvgTicketValue, Error> = .success(
        AvgTicketValue(currentCents: 5000, previousCents: 4500, trendPct: 11.1)
    )
    var employeesResult: Result<[EmployeePerf], Error> = .success([])
    var inventoryResult: Result<[InventoryTurnoverRow], Error> = .success([])
    var inventoryReportResult: Result<InventoryReport, Error> = .success(
        InventoryReport(outOfStockCount: 0, lowStockCount: 0, valueSummary: [], topMoving: [])
    )
    var expensesResult: Result<ExpensesReport, Error> = .success(
        ExpensesReport(totalDollars: 1200.0, revenueDollars: 5000.0)
    )
    var csatResult: Result<CSATScore, Error> = .failure(
        ReportsRepositoryError.endpointNotImplemented("/reports/csat")
    )
    var npsResult: Result<NPSScore, Error> = .success(
        NPSScore(current: 60, previous: 55, promoterPct: 70, detractorPct: 10, themes: ["Speed", "Quality"])
    )
    var drillResult: Result<[DrillThroughRecord], Error> = .success([
        DrillThroughRecord(id: 1, label: "2024-01-01", detail: "3 sales", amountCents: 30000)
    ])
    private(set) var drillCallCount = 0
    private(set) var drillLastMetric: String?
    private(set) var drillLastDate: String?
    var scheduledResult: Result<[ScheduledReport], Error> = .success([])
    var createScheduledResult: Result<ScheduledReport, Error> = .success(
        ScheduledReport(id: 1, reportType: "revenue", frequency: .weekly,
                        recipientEmails: ["a@b.com"], isActive: true, nextRunAt: nil)
    )
    var emailReportError: Error? = nil
    var technicianResult: Result<[TechnicianPerfRow], Error> = .success([])
    var taxReportResult: Result<TaxReportResponse, Error> = .success(TaxReportResponse())
    // §15.2
    var topCustomersResult: Result<[TopCustomerRow], Error> = .success([])
    // §15.3
    var ticketsTrendResult: Result<[TicketDayPoint], Error> = .success([])
    var busyHoursResult: Result<[BusyHourCell], Error> = .success([])
    var slaSummaryResult: Result<SLABreachSummary, Error> = .failure(
        ReportsRepositoryError.endpointNotImplemented("/reports/sla")
    )

    // MARK: - Call tracking

    private(set) var revenueCallCount = 0
    private(set) var revenueLastGroupBy: String?
    private(set) var revenueLastFrom: String?
    private(set) var scheduledDeletedIds: [Int64] = []
    private(set) var emailCallCount = 0

    // MARK: - Protocol conformance

    func getRevenue(from: String, to: String, groupBy: String) async throws -> [RevenuePoint] {
        revenueCallCount += 1
        revenueLastFrom = from
        revenueLastGroupBy = groupBy
        return try revenueResult.get()
    }

    func getSalesReport(from: String, to: String, groupBy: String) async throws -> SalesReportResponse {
        revenueCallCount += 1
        revenueLastFrom = from
        revenueLastGroupBy = groupBy
        return try salesReportResult.get()
    }

    func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint] {
        try ticketsResult.get()
    }

    func getTicketsReport(from: String, to: String) async throws -> TicketsReportResponse {
        try ticketsReportResult.get()
    }

    func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue {
        try avgTicketResult.get()
    }

    func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf] {
        try employeesResult.get()
    }

    func getInventoryReport(from: String, to: String) async throws -> InventoryReport {
        try inventoryReportResult.get()
    }

    func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow] {
        try inventoryResult.get()
    }

    func getExpensesReport(from: String, to: String) async throws -> ExpensesReport {
        try expensesResult.get()
    }

    func getCSAT(from: String, to: String) async throws -> CSATScore {
        try csatResult.get()
    }

    func getNPS(from: String, to: String) async throws -> NPSScore {
        try npsResult.get()
    }

    func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord] {
        drillCallCount += 1
        drillLastMetric = metric
        drillLastDate = date
        return try drillResult.get()
    }

    func getScheduledReports() async throws -> [ScheduledReport] {
        try scheduledResult.get()
    }

    func createScheduledReport(reportType: String, frequency: String, emails: [String]) async throws -> ScheduledReport {
        try createScheduledResult.get()
    }

    func deleteScheduledReport(id: Int64) async throws {
        scheduledDeletedIds.append(id)
    }

    func emailReport(recipient: String, pdfBase64: String) async throws {
        emailCallCount += 1
        if let err = emailReportError { throw err }
    }

    func getTechnicianPerformance(from: String, to: String) async throws -> [TechnicianPerfRow] {
        try technicianResult.get()
    }

    func getTaxReport(from: String, to: String) async throws -> TaxReportResponse {
        try taxReportResult.get()
    }

    // §15.2
    func getTopCustomers(from: String, to: String) async throws -> [TopCustomerRow] {
        try topCustomersResult.get()
    }

    // §15.3
    func getTicketsTrend(from: String, to: String) async throws -> [TicketDayPoint] {
        try ticketsTrendResult.get()
    }

    func getBusyHours(from: String, to: String) async throws -> [BusyHourCell] {
        try busyHoursResult.get()
    }

    func getSLASummary(from: String, to: String) async throws -> SLABreachSummary {
        try slaSummaryResult.get()
    }
}

// MARK: - Actor mutators for tests

extension StubReportsRepository {
    func setRevenueResult(_ result: Result<[RevenuePoint], Error>) {
        revenueResult = result
    }
    func setSalesReportResult(_ result: Result<SalesReportResponse, Error>) {
        salesReportResult = result
    }
    func setTicketsResult(_ result: Result<[TicketStatusPoint], Error>) {
        ticketsResult = result
    }
    func setTicketsReportResult(_ result: Result<TicketsReportResponse, Error>) {
        ticketsReportResult = result
    }
    func setEmployeesResult(_ result: Result<[EmployeePerf], Error>) {
        employeesResult = result
    }
    func setInventoryResult(_ result: Result<[InventoryTurnoverRow], Error>) {
        inventoryResult = result
    }
    func setInventoryReportResult(_ result: Result<InventoryReport, Error>) {
        inventoryReportResult = result
    }
    func setExpensesResult(_ result: Result<ExpensesReport, Error>) {
        expensesResult = result
    }
    func setNPSResult(_ result: Result<NPSScore, Error>) {
        npsResult = result
    }
    func setDrillResult(_ result: Result<[DrillThroughRecord], Error>) {
        drillResult = result
    }
}

// MARK: - Test fixtures

extension RevenuePoint {
    static func fixture(id: Int64 = 1, date: String = "2024-01-01",
                        amountCents: Int64 = 10000, saleCount: Int = 5) -> RevenuePoint {
        RevenuePoint(id: id, date: date, amountCents: amountCents, saleCount: saleCount)
    }
}

extension TicketStatusPoint {
    static func fixture(id: Int64 = 1, status: String = "Open",
                        count: Int = 10, color: String? = nil) -> TicketStatusPoint {
        TicketStatusPoint(id: id, status: status, count: count, color: color)
    }
}

extension EmployeePerf {
    static func fixture(id: Int64 = 1, name: String = "Alice",
                        tickets: Int = 20, revenue: Int64 = 500000, hours: Double = 2.5) -> EmployeePerf {
        EmployeePerf(id: id, employeeName: name, ticketsClosed: tickets,
                     revenueCents: revenue, avgResolutionHours: hours)
    }
}

extension InventoryTurnoverRow {
    static func fixture(id: Int64 = 1, sku: String = "SKU001",
                        name: String = "Widget", rate: Double = 2.5,
                        days: Double = 45.0) -> InventoryTurnoverRow {
        InventoryTurnoverRow(id: id, sku: sku, name: name, turnoverRate: rate, daysOnHand: days)
    }
}

extension InventoryMovementItem {
    static func fixture(name: String = "Screen Protector", sku: String? = "SP01",
                        usedQty: Int = 10, inStock: Int = 50) -> InventoryMovementItem {
        InventoryMovementItem(name: name, sku: sku, usedQty: usedQty, inStock: inStock)
    }
}

extension ExpenseDayPoint {
    static func fixture(date: String = "2024-01-01",
                        revenue: Double = 1000.0, cogs: Double = 400.0) -> ExpenseDayPoint {
        ExpenseDayPoint(date: date, revenue: revenue, cogs: cogs)
    }
}

// MARK: - Stub error

enum RepoTestError: Error { case bang }
