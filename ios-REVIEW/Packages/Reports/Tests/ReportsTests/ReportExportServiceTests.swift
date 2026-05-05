import XCTest
@testable import Reports

// MARK: - ReportExportServiceTests

final class ReportExportServiceTests: XCTestCase {

    private func makeSnapshot() -> ReportSnapshot {
        ReportSnapshot(
            title: "Test Report",
            period: "2024-01-01 – 2024-01-31",
            revenue: [
                RevenuePoint.fixture(id: 1, amountCents: 10000),
                RevenuePoint.fixture(id: 2, amountCents: 20000)
            ],
            ticketsByStatus: [
                TicketStatusPoint.fixture(status: "Open", count: 5),
                TicketStatusPoint.fixture(id: 2, status: "Closed", count: 15)
            ],
            avgTicketValue: AvgTicketValue(currentCents: 5000, previousCents: 4500, trendPct: 11.0),
            topEmployees: [EmployeePerf.fixture()],
            inventoryTurnover: [InventoryTurnoverRow.fixture()],
            csatScore: CSATScore(current: 4.5, previous: 4.2, responseCount: 100, trendPct: 7.1),
            npsScore: NPSScore(current: 60, previous: 55, promoterPct: 70, detractorPct: 10, themes: ["Speed"])
        )
    }

    // MARK: - generatePDF

    func test_generatePDF_returnsNonEmptyURL() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let snapshot = makeSnapshot()
        let url = try await service.generatePDF(report: snapshot)
        XCTAssertFalse(url.path.isEmpty)
    }

    func test_generatePDF_fileExists() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let url = try await service.generatePDF(report: makeSnapshot())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func test_generatePDF_fileNotEmpty() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let url = try await service.generatePDF(report: makeSnapshot())
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 0)
    }

    func test_generatePDF_fileHasPDFHeader() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let url = try await service.generatePDF(report: makeSnapshot())
        let data = try Data(contentsOf: url)
        // PDF files start with %PDF
        let header = String(data: data.prefix(4), encoding: .utf8)
        XCTAssertEqual(header, "%PDF")
    }

    func test_generatePDF_multipleCallsReturnDifferentURLs() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let snapshot = makeSnapshot()
        let url1 = try await service.generatePDF(report: snapshot)
        // Brief delay so timestamps differ
        try await Task.sleep(nanoseconds: 1_100_000_000)
        let url2 = try await service.generatePDF(report: snapshot)
        XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent)
    }

    // MARK: - emailReport

    func test_emailReport_callsRepository() async throws {
        let stub = StubReportsRepository()
        let service = ReportExportService(repository: stub)
        let url = try await service.generatePDF(report: makeSnapshot())
        try await service.emailReport(pdf: url, recipient: "test@example.com")
        let count = await stub.emailCallCount
        XCTAssertEqual(count, 1)
    }

    func test_emailReport_propagatesRepositoryError() async throws {
        let stub = StubReportsRepository()
        await stub.setEmailError(RepoTestError.bang)
        let service = ReportExportService(repository: stub)
        let url = try await service.generatePDF(report: makeSnapshot())
        do {
            try await service.emailReport(pdf: url, recipient: "test@example.com")
            XCTFail("Expected error")
        } catch { /* expected */ }
    }
}

// MARK: - StubReportsRepository email error setter

extension StubReportsRepository {
    func setEmailError(_ error: Error?) {
        emailReportError = error
    }
}
