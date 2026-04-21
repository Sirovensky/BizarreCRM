import Foundation
import Networking

// MARK: - ReportsRepository (protocol)

public protocol ReportsRepository: Sendable {
    func getRevenue(from: String, to: String, groupBy: String) async throws -> [RevenuePoint]
    func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint]
    func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue
    func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf]
    func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow]
    func getCSAT(from: String, to: String) async throws -> CSATScore
    func getNPS(from: String, to: String) async throws -> NPSScore
    func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord]
    func getScheduledReports() async throws -> [ScheduledReport]
    func createScheduledReport(reportType: String, frequency: String, emails: [String]) async throws -> ScheduledReport
    func deleteScheduledReport(id: Int64) async throws
    func emailReport(recipient: String, pdfBase64: String) async throws
}

// MARK: - LiveReportsRepository

public actor LiveReportsRepository: ReportsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    // MARK: - Revenue

    public func getRevenue(from: String, to: String, groupBy: String = "day") async throws -> [RevenuePoint] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "groupBy", value: groupBy)
        ]
        return try await api.get("/api/v1/reports/revenue", query: query, as: [RevenuePoint].self)
    }

    // MARK: - Tickets by Status

    public func getTicketsByStatus(from: String, to: String) async throws -> [TicketStatusPoint] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/tickets-by-status", query: query, as: [TicketStatusPoint].self)
    }

    // MARK: - Avg Ticket Value

    public func getAvgTicketValue(from: String, to: String) async throws -> AvgTicketValue {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/avg-ticket-value", query: query, as: AvgTicketValue.self)
    }

    // MARK: - Employees Performance

    public func getEmployeesPerformance(from: String, to: String) async throws -> [EmployeePerf] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/employees-performance", query: query, as: [EmployeePerf].self)
    }

    // MARK: - Inventory Turnover

    public func getInventoryTurnover(from: String, to: String) async throws -> [InventoryTurnoverRow] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/inventory-turnover", query: query, as: [InventoryTurnoverRow].self)
    }

    // MARK: - CSAT

    public func getCSAT(from: String, to: String) async throws -> CSATScore {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/csat", query: query, as: CSATScore.self)
    }

    // MARK: - NPS

    public func getNPS(from: String, to: String) async throws -> NPSScore {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to)
        ]
        return try await api.get("/api/v1/reports/nps", query: query, as: NPSScore.self)
    }

    // MARK: - Drill-through

    public func getDrillThrough(metric: String, date: String) async throws -> [DrillThroughRecord] {
        let query: [URLQueryItem] = [
            URLQueryItem(name: "metric", value: metric),
            URLQueryItem(name: "date", value: date)
        ]
        return try await api.get("/api/v1/reports/drill-through", query: query, as: [DrillThroughRecord].self)
    }

    // MARK: - Scheduled Reports

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

    // MARK: - Email Report

    public func emailReport(recipient: String, pdfBase64: String) async throws {
        let body = EmailReportRequest(recipient: recipient, pdfBase64: pdfBase64)
        _ = try await api.post("/api/v1/reports/email", body: body, as: EmptyReportPayload.self)
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
