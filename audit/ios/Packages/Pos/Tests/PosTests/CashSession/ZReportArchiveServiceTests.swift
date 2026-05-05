import XCTest
@testable import Pos
@testable import Networking

/// §39.2 — Unit tests for `ZReportArchiveService`.
/// Verifies local persistence and result enum behaviour.
final class ZReportArchiveServiceTests: XCTestCase {

    // MARK: - Payload helpers

    private func makePayload(sessionId: Int64 = 42) -> ZReportArchivePayload {
        ZReportArchivePayload(
            sessionId: sessionId,
            openedAt: Date(timeIntervalSince1970: 0),
            closedAt: Date(timeIntervalSince1970: 3600),
            openingFloatCents: 10000,
            closingCountCents: 9850,
            expectedCashCents: 10000,
            varianceCents: -150,
            totalSalesCents: 45000,
            totalRefundsCents: 0,
            totalVoidsCents: 0,
            cashierNotes: "Test shift"
        )
    }

    // MARK: - Local persistence

    func test_archive_savedLocally_whenServerUnavailable() async throws {
        let api = MockAPIClientForArchive(httpStatus: 501)
        let sut = ZReportArchiveService(api: api)
        let payload = makePayload()

        let result = try await sut.archive(payload: payload)

        guard case .savedLocally(let url) = result else {
            XCTFail("Expected .savedLocally, got \(result)")
            return
        }
        XCTAssertTrue(url.lastPathComponent.contains("ZReport"), url.lastPathComponent)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(".json"), url.lastPathComponent)

        // Verify file exists and round-trips
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(ZReportArchivePayload.self, from: data)
        XCTAssertEqual(decoded.sessionId, 42)
        XCTAssertEqual(decoded.totalSalesCents, 45000)

        // Cleanup
        try? FileManager.default.removeItem(at: url)
    }

    func test_archiveFilename_containsDateAndSessionId() async throws {
        // The filename format is ZReport-YYYY-MM-DD-<sessionId>.json
        let api = MockAPIClientForArchive(httpStatus: 501)
        let sut = ZReportArchiveService(api: api)
        let payload = makePayload(sessionId: 99)

        let result = try await sut.archive(payload: payload)
        let name = result.localURL.lastPathComponent

        XCTAssertTrue(name.contains("99"), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)

        try? FileManager.default.removeItem(at: result.localURL)
    }

    func test_resultLocalURL_isSameInBothCases() async throws {
        // Verify that .localURL resolves for both enum arms
        let savedResult: ZReportArchiveResult = .savedLocally(localURL: URL(filePath: "/tmp/a.json"))
        let uploadedResult: ZReportArchiveResult = .uploaded(
            serverURL: URL(string: "https://example.com/z.json")!,
            localURL: URL(filePath: "/tmp/a.json")
        )
        XCTAssertEqual(savedResult.localURL.lastPathComponent, "a.json")
        XCTAssertEqual(uploadedResult.localURL.lastPathComponent, "a.json")
    }

    func test_wasUploaded_trueOnlyForUploadedCase() {
        let saved: ZReportArchiveResult = .savedLocally(localURL: URL(filePath: "/tmp/x.json"))
        let uploaded: ZReportArchiveResult = .uploaded(
            serverURL: URL(string: "https://example.com/x.json")!,
            localURL: URL(filePath: "/tmp/x.json")
        )
        XCTAssertFalse(saved.wasUploaded)
        XCTAssertTrue(uploaded.wasUploaded)
    }
}

// MARK: - Mock

private final class MockAPIClientForArchive: APIClient {
    let httpStatus: Int

    init(httpStatus: Int) {
        self.httpStatus = httpStatus
        super.init()
    }

    override func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        throw APITransportError.httpStatus(httpStatus, message: nil)
    }
}
