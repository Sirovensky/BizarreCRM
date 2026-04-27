import Foundation
import Networking

// MARK: - ReportsRepository (protocol)

public protocol ReportsRepository: Sendable {
    // Revenue — wired to GET /api/v1/reports/sales
    func getRevenue(from: String, to: String, groupBy: String) async throws -> [RevenuePoint]
    func getSalesReport(from: String, to: String, groupBy: String) async throws -> SalesReportResponse
    // Tickets — wired to GET /api/v1/reports/tickets
    func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint]
    func getTicketsReport(from: String, to: String) async throws -> TicketsReportResponse
    // Avg ticket value — derived from GET /api/v1/reports/tickets
    func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue
    // Employees — wired to GET /api/v1/reports/employees
    func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf]
    // Inventory — wired to GET /api/v1/reports/inventory
    func getInventoryReport(from: String, to: String) async throws -> InventoryReport
    func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow]
    // Expenses — derived from GET /api/v1/reports/dashboard-kpis
    func getExpensesReport(from: String, to: String) async throws -> ExpensesReport
    // CSAT / NPS — endpoint stubs: server routes not yet present; graceful fallback
    func getCSAT(from: String, to: String) async throws -> CSATScore
    func getNPS(from: String, to: String) async throws -> NPSScore
    // Drill-through — endpoint stub
    func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord]
    // Scheduled reports — wired to GET /api/v1/reports/scheduled
    func getScheduledReports() async throws -> [ScheduledReport]
    func createScheduledReport(reportType: String, frequency: String, emails: [String]) async throws -> ScheduledReport
    func deleteScheduledReport(id: Int64) async throws
    // Email report
    func emailReport(recipient: String, pdfBase64: String) async throws
    // §15.4 Technician performance — GET /api/v1/reports/technician-performance
    func getTechnicianPerformance(from: String, to: String) async throws -> [TechnicianPerfRow]
    // §15.6 Tax report — GET /api/v1/reports/tax
    func getTaxReport(from: String, to: String) async throws -> TaxReportResponse
}

// MARK: - LiveReportsRepository

public actor LiveReportsRepository: ReportsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Revenue → GET /api/v1/reports/sales

    public func getRevenue(from: String, to: String, groupBy: String = "day") async throws -> [RevenuePoint] {
        let report = try await getSalesReport(from: from, to: to, groupBy: groupBy)
        return report.rows
    }

    public func getSalesReport(from: String, to: String, groupBy: String = "day") async throws -> SalesReportResponse {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to),
            URLQueryItem(name: "group_by", value: groupBy)
        ]
        return try await api.get("/api/v1/reports/sales", query: query, as: SalesReportResponse.self)
    }

    // MARK: - Tickets → GET /api/v1/reports/tickets

    public func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint] {
        let report = try await getTicketsReport(from: from, to: to)
        return report.byStatus
    }

    public func getTicketsReport(from: String, to: String) async throws -> TicketsReportResponse {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to)
        ]
        return try await api.get("/api/v1/reports/tickets", query: query, as: TicketsReportResponse.self)
    }

    // MARK: - Avg Ticket Value → derived from GET /api/v1/reports/tickets

    public func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue {
        let report = try await getTicketsReport(from: from, to: to)
        let current = report.summary.avgTicketValue
        // Compute previous period of same length for trend
        let (prevFrom, prevTo) = previousPeriod(from: from, to: to)
        let prevReport = try? await getTicketsReport(from: prevFrom, to: prevTo)
        let previous = prevReport?.summary.avgTicketValue ?? current
        return AvgTicketValue(currentDollars: current, previousDollars: previous)
    }

    // MARK: - Employees → GET /api/v1/reports/employees

    public func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to)
        ]
        let response = try await api.get("/api/v1/reports/employees", query: query, as: EmployeesReportResponse.self)
        return response.rows
    }

    // MARK: - Inventory → GET /api/v1/reports/inventory

    public func getInventoryReport(from: String, to: String) async throws -> InventoryReport {
        let response = try await api.get("/api/v1/reports/inventory", as: InventoryReportResponse.self)
        return InventoryReport(
            outOfStockCount: response.outOfStock,
            lowStockCount: response.lowStock.count,
            valueSummary: response.valueSummary,
            topMoving: response.topMoving
        )
    }

    /// Inventory turnover by category → GET /api/v1/reports/inventory-turnover
    public func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow] {
        struct TurnoverResponse: Decodable, Sendable {
            let byCategory: [InventoryTurnoverRow]
            enum CodingKeys: String, CodingKey { case byCategory = "by_category" }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self.byCategory = (try? c.decode([InventoryTurnoverRow].self, forKey: .byCategory)) ?? []
            }
        }
        let response = try await api.get("/api/v1/reports/inventory-turnover", as: TurnoverResponse.self)
        return response.byCategory
    }

    // MARK: - Expenses → derived from GET /api/v1/reports/dashboard-kpis

    public func getExpensesReport(from: String, to: String) async throws -> ExpensesReport {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to)
        ]
        let kpis = try await api.get("/api/v1/reports/dashboard-kpis", query: query, as: DashboardKpisResponse.self)
        let dailyBreakdown = kpis.dailySales.map { day in
            ExpenseDayPoint(date: day.date, revenue: day.sale, cogs: day.cogs)
        }
        return ExpensesReport(
            totalDollars: kpis.expenses,
            revenueDollars: kpis.totalSales,
            dailyBreakdown: dailyBreakdown
        )
    }

    // MARK: - CSAT — endpoint stub (GET /api/v1/reports/csat not yet on server)
    // Returns a neutral placeholder so the UI degrades gracefully.

    public func getCSAT(from: String, to: String) async throws -> CSATScore {
        // When the server implements /reports/csat, replace this body with:
        // let query = [URLQueryItem(name: "from_date", value: from), ...]
        // return try await api.get("/api/v1/reports/csat", query: query, as: CSATScore.self)
        throw ReportsRepositoryError.endpointNotImplemented("/reports/csat")
    }

    // MARK: - NPS — wired to GET /api/v1/reports/nps-trend (best available)

    public func getNPS(from: String, to: String) async throws -> NPSScore {
        struct NpsTrendResponse: Decodable, Sendable {
            let currentNps: Int?
            let overall: NpsOverall?
            enum CodingKeys: String, CodingKey {
                case currentNps = "current_nps"
                case overall
            }
        }
        struct NpsOverall: Decodable, Sendable {
            let promoters: Int
            let passives: Int
            let detractors: Int
            let nps: Double
        }
        let response = try await api.get("/api/v1/reports/nps-trend", as: NpsTrendResponse.self)
        let overall = response.overall
        let total = Double((overall?.promoters ?? 0) + (overall?.passives ?? 0) + (overall?.detractors ?? 0))
        let promoterPct = total > 0 ? (Double(overall?.promoters ?? 0) / total) * 100.0 : 0.0
        let detractorPct = total > 0 ? (Double(overall?.detractors ?? 0) / total) * 100.0 : 0.0
        return NPSScore(
            current: Int(overall?.nps ?? 0),
            previous: 0,
            promoterPct: promoterPct,
            detractorPct: detractorPct,
            themes: []
        )
    }

    // MARK: - Drill-through → GET /api/v1/reports/sales (single-day slice)
    //
    // The server has no dedicated drill-through endpoint.
    // For `metric == "revenue"` we fetch /reports/sales narrowed to the
    // exact date (from_date == to_date == date, group_by=day).
    // Each row in the response becomes a DrillThroughRecord.

    public func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord] {
        guard metric == "revenue" else {
            // Other metrics have no drill-through endpoint yet.
            throw ReportsRepositoryError.endpointNotImplemented("/reports/drill-through[\(metric)]")
        }

        // Narrow the sales report to a single day.
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: date),
            URLQueryItem(name: "to_date",   value: date),
            URLQueryItem(name: "group_by",  value: "day")
        ]
        let response = try await api.get(
            "/api/v1/reports/sales", query: query, as: SalesReportResponse.self
        )

        // Map each revenue row to a DrillThroughRecord.
        return response.rows.enumerated().map { idx, row in
            DrillThroughRecord(
                id: Int64(idx + 1),
                label: row.date,
                detail: "\(row.saleCount) sale\(row.saleCount == 1 ? "" : "s")",
                amountCents: row.amountCents
            )
        }
    }

    // MARK: - Scheduled Reports → GET /api/v1/reports/scheduled

    public func getScheduledReports() async throws -> [ScheduledReport] {
        try await api.get("/api/v1/reports/scheduled", as: [ScheduledReport].self)
    }

    public func createScheduledReport(reportType: String, frequency: String, emails: [String]) async throws -> ScheduledReport {
        let body = ScheduledReportRequest(reportType: reportType, frequency: frequency, recipientEmails: emails)
        return try await api.post("/api/v1/reports/scheduled", body: body, as: ScheduledReport.self)
    }

    public func deleteScheduledReport(id: Int64) async throws {
        try await api.delete("/api/v1/reports/scheduled/\(id)")
    }

    // MARK: - Email Report → POST /api/v1/reports/email

    public func emailReport(recipient: String, pdfBase64: String) async throws {
        let body = EmailReportRequest(recipient: recipient, pdfBase64: pdfBase64)
        _ = try await api.post("/api/v1/reports/email", body: body, as: EmptyReportPayload.self)
    }

    // MARK: - Technician Performance → GET /api/v1/reports/technician-performance

    public func getTechnicianPerformance(from: String, to: String) async throws -> [TechnicianPerfRow] {
        struct TechPerfResponse: Decodable, Sendable {
            let rows: [TechnicianPerfRow]
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                rows = (try? c.decode([TechnicianPerfRow].self, forKey: .rows)) ?? []
            }
            enum CodingKeys: String, CodingKey { case rows }
        }
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to)
        ]
        let response = try await api.get(
            "/api/v1/reports/technician-performance", query: query, as: TechPerfResponse.self
        )
        return response.rows
    }

    // MARK: - Tax Report → GET /api/v1/reports/tax

    public func getTaxReport(from: String, to: String) async throws -> TaxReportResponse {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from_date", value: from),
            URLQueryItem(name: "to_date", value: to)
        ]
        return try await api.get("/api/v1/reports/tax", query: query, as: TaxReportResponse.self)
    }

    // MARK: - Private helpers

    /// Compute the previous period of equal length for period-over-period comparison.
    private func previousPeriod(from fromStr: String, to toStr: String) -> (String, String) {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        guard let f = fmt.date(from: fromStr), let t = fmt.date(from: toStr) else {
            return (fromStr, toStr)
        }
        let duration = t.timeIntervalSince(f)
        let prevTo = f.addingTimeInterval(-86400)
        let prevFrom = prevTo.addingTimeInterval(-duration)
        return (fmt.string(from: prevFrom), fmt.string(from: prevTo))
    }
}

// MARK: - Errors

public enum ReportsRepositoryError: Error, LocalizedError, Sendable {
    case endpointNotImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .endpointNotImplemented(let path):
            return "Server endpoint \(path) is not yet implemented."
        }
    }
}

// MARK: - Request Bodies (private)

private struct ScheduledReportRequest: Encodable, Sendable {
    let reportType: String
    let frequency: String
    let recipientEmails: [String]

    enum CodingKeys: String, CodingKey {
        case reportType      = "report_type"
        case frequency
        case recipientEmails = "recipient_emails"
    }
}

private struct EmailReportRequest: Encodable, Sendable {
    let recipient: String
    let pdfBase64: String

    enum CodingKeys: String, CodingKey {
        case recipient
        case pdfBase64 = "pdf_base64"
    }
}

private struct EmptyReportPayload: Decodable, Sendable {}
