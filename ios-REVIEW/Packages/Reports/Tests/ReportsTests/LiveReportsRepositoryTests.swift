import XCTest
@testable import Reports
import Networking

// MARK: - LiveReportsRepositoryTests
// Tests happy-path and error-path for LiveReportsRepository.
// Uses a StubAPIClient that returns canned JSON or throws.

final class LiveReportsRepositoryTests: XCTestCase {

    // MARK: - Revenue happy path

    func test_getRevenue_returnsDecodedPoints() async throws {
        let json = """
        {"success":true,"data":[{"id":1,"date":"2024-01-01","amount_cents":5000,"sale_count":3}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let points = try await repo.getRevenue(from: "2024-01-01", to: "2024-01-31", groupBy: "day")
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].amountCents, 5000)
        XCTAssertEqual(points[0].saleCount, 3)
    }

    func test_getRevenue_propagatesError() async {
        let api = StubAPIClientForReports(shouldThrow: true)
        let repo = LiveReportsRepository(api: api)
        do {
            _ = try await repo.getRevenue(from: "2024-01-01", to: "2024-01-31", groupBy: "day")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }

    // MARK: - TicketsByStatus happy path

    func test_getTicketsByStatus_returnsPoints() async throws {
        let json = """
        {"success":true,"data":[{"id":1,"status":"Open","count":10},{"id":2,"status":"Closed","count":25}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let pts = try await repo.getTicketsByStatus(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(pts.count, 2)
        XCTAssertEqual(pts[0].status, "Open")
    }

    func test_getTicketsByStatus_propagatesError() async {
        let api = StubAPIClientForReports(shouldThrow: true)
        let repo = LiveReportsRepository(api: api)
        do {
            _ = try await repo.getTicketsByStatus(from: "2024-01-01", to: "2024-01-31")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }

    // MARK: - AvgTicketValue

    func test_getAvgTicketValue_returnsValue() async throws {
        let json = """
        {"success":true,"data":{"current_cents":7500,"previous_cents":6800,"trend_pct":10.3}}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let atv = try await repo.getAvgTicketValue(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(atv.currentCents, 7500)
        XCTAssertEqual(atv.trendPct, 10.3, accuracy: 0.001)
    }

    func test_getAvgTicketValue_propagatesError() async {
        let api = StubAPIClientForReports(shouldThrow: true)
        let repo = LiveReportsRepository(api: api)
        do {
            _ = try await repo.getAvgTicketValue(from: "2024-01-01", to: "2024-01-31")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }

    // MARK: - EmployeesPerformance

    func test_getEmployeesPerformance_returnsArray() async throws {
        let json = """
        {"success":true,"data":[{"id":1,"employee_name":"Alice","tickets_closed":20,"revenue_cents":500000,"avg_resolution_hours":2.5}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let emps = try await repo.getEmployeesPerformance(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(emps.count, 1)
        XCTAssertEqual(emps[0].employeeName, "Alice")
        XCTAssertEqual(emps[0].ticketsClosed, 20)
    }

    // MARK: - InventoryTurnover

    func test_getInventoryTurnover_returnsRows() async throws {
        let json = """
        {"success":true,"data":[{"id":1,"sku":"SKU001","name":"Widget","turnover_rate":2.1,"days_on_hand":47.3}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let rows = try await repo.getInventoryTurnover(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].sku, "SKU001")
        XCTAssertEqual(rows[0].daysOnHand, 47.3, accuracy: 0.001)
    }

    // MARK: - CSAT

    func test_getCSAT_returnsScore() async throws {
        let json = """
        {"success":true,"data":{"current":4.7,"previous":4.3,"response_count":200,"trend_pct":9.3}}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let score = try await repo.getCSAT(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(score.current, 4.7, accuracy: 0.001)
        XCTAssertEqual(score.responseCount, 200)
    }

    func test_getCSAT_propagatesError() async {
        let api = StubAPIClientForReports(shouldThrow: true)
        let repo = LiveReportsRepository(api: api)
        do {
            _ = try await repo.getCSAT(from: "2024-01-01", to: "2024-01-31")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }

    // MARK: - NPS

    func test_getNPS_returnsScore() async throws {
        let json = """
        {"success":true,"data":{"current":62,"previous":55,"promoter_pct":70.0,"detractor_pct":8.0,"themes":["Speed","Value"]}}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let score = try await repo.getNPS(from: "2024-01-01", to: "2024-01-31")
        XCTAssertEqual(score.current, 62)
        XCTAssertEqual(score.themes, ["Speed", "Value"])
    }

    func test_getNPS_propagatesError() async {
        let api = StubAPIClientForReports(shouldThrow: true)
        let repo = LiveReportsRepository(api: api)
        do {
            _ = try await repo.getNPS(from: "2024-01-01", to: "2024-01-31")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }

    // MARK: - DrillThrough

    func test_getDrillThrough_returnsRecords() async throws {
        let json = """
        {"success":true,"data":[{"id":10,"label":"Sale #10","detail":"iPhone 15 screen","amount_cents":25000}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let records = try await repo.getDrillThrough(metric: "revenue", date: "2024-01-15")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].amountCents, 25000)
    }

    // MARK: - Scheduled Reports

    func test_getScheduledReports_returnsArray() async throws {
        let json = """
        {"success":true,"data":[{"id":1,"report_type":"revenue","frequency":"weekly","recipient_emails":["a@b.com"],"is_active":true,"next_run_at":null}]}
        """
        let api = StubAPIClientForReports(json: json)
        let repo = LiveReportsRepository(api: api)
        let schedules = try await repo.getScheduledReports()
        XCTAssertEqual(schedules.count, 1)
        XCTAssertEqual(schedules[0].frequency, .weekly)
    }

    func test_deleteScheduledReport_callsCorrectPath() async throws {
        let api = StubAPIClientForReports(json: "{\"success\":true,\"data\":null}")
        let repo = LiveReportsRepository(api: api)
        // Should not throw.
        try await repo.deleteScheduledReport(id: 42)
        let path = await api.lastDeletedPath
        XCTAssertEqual(path, "/api/v1/reports/scheduled/42")
    }
}

// MARK: - StubAPIClientForReports

actor StubAPIClientForReports: APIClient {
    private let json: String
    private let shouldThrow: Bool
    private(set) var lastDeletedPath: String?

    init(json: String = "{\"success\":true,\"data\":[]}", shouldThrow: Bool = false) {
        self.json = json
        self.shouldThrow = shouldThrow
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if shouldThrow { throw APITransportError.noBaseURL }
        let data = json.data(using: .utf8)!
        // Models use explicit CodingKeys with snake_case — no convertFromSnakeCase strategy.
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(APIResponse<T>.self, from: data)
        guard let payload = envelope.data else {
            throw APITransportError.envelopeFailure(message: "no data")
        }
        return payload
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldThrow { throw APITransportError.noBaseURL }
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(APIResponse<T>.self, from: data)
        guard let payload = envelope.data else {
            throw APITransportError.envelopeFailure(message: "no data")
        }
        return payload
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func delete(_ path: String) async throws {
        lastDeletedPath = path
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
