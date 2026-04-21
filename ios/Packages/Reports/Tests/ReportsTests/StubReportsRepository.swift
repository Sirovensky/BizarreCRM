import Foundation
@testable import Reports

// MARK: - StubReportsRepository

actor StubReportsRepository: ReportsRepository {

    // MARK: - Canned results

    var revenueResult: Result<[RevenuePoint], Error> = .success([])
    var ticketsResult: Result<[TicketStatusPoint], Error> = .success([])
    var avgTicketResult: Result<AvgTicketValue, Error> = .success(AvgTicketValue(currentCents: 5000, previousCents: 4500, trendPct: 11.1))
    var employeesResult: Result<[EmployeePerf], Error> = .success([])
    var inventoryResult: Result<[InventoryTurnoverRow], Error> = .success([])
    var csatResult: Result<CSATScore, Error> = .success(CSATScore(current: 4.5, previous: 4.2, responseCount: 100, trendPct: 7.1))
    var npsResult: Result<NPSScore, Error> = .success(NPSScore(current: 60, previous: 55, promoterPct: 70, detractorPct: 10, themes: ["Speed", "Quality"]))
    var drillResult: Result<[DrillThroughRecord], Error> = .success([])
    var scheduledResult: Result<[ScheduledReport], Error> = .success([])
    var createScheduledResult: Result<ScheduledReport, Error> = .success(ScheduledReport(id: 1, reportType: "revenue", frequency: .weekly, recipientEmails: ["a@b.com"], isActive: true, nextRunAt: nil))
    var emailReportError: Error? = nil

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

    func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint] {
        try ticketsResult.get()
    }

    func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue {
        try avgTicketResult.get()
    }

    func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf] {
        try employeesResult.get()
    }

    func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow] {
        try inventoryResult.get()
    }

    func getCSAT(from: String, to: String) async throws -> CSATScore {
        try csatResult.get()
    }

    func getNPS(from: String, to: String) async throws -> NPSScore {
        try npsResult.get()
    }

    func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord] {
        try drillResult.get()
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
}

// MARK: - Test fixtures

extension RevenuePoint {
    static func fixture(id: Int64 = 1, date: String = "2024-01-01", amountCents: Int64 = 10000, saleCount: Int = 5) -> RevenuePoint {
        RevenuePoint(id: id, date: date, amountCents: amountCents, saleCount: saleCount)
    }
}

extension TicketStatusPoint {
    static func fixture(id: Int64 = 1, status: String = "Open", count: Int = 10) -> TicketStatusPoint {
        TicketStatusPoint(id: id, status: status, count: count)
    }
}

extension EmployeePerf {
    static func fixture(id: Int64 = 1, name: String = "Alice", tickets: Int = 20, revenue: Int64 = 5000_00, hours: Double = 2.5) -> EmployeePerf {
        EmployeePerf(id: id, employeeName: name, ticketsClosed: tickets, revenueCents: revenue, avgResolutionHours: hours)
    }
}

extension InventoryTurnoverRow {
    static func fixture(id: Int64 = 1, sku: String = "SKU001", name: String = "Widget", rate: Double = 2.5, days: Double = 45.0) -> InventoryTurnoverRow {
        InventoryTurnoverRow(id: id, sku: sku, name: name, turnoverRate: rate, daysOnHand: days)
    }
}

// MARK: - Stub error

enum RepoTestError: Error { case bang }
