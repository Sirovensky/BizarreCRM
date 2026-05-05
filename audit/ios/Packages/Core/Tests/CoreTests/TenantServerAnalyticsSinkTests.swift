import XCTest
@testable import Core

// MARK: — Stub session

final class AnalyticsSinkStub: AnalyticsURLSessionProtocol, @unchecked Sendable {
    var capturedRequests: [URLRequest] = []
    var responseData: Data = Data()
    var responseCode: Int = 200
    var shouldThrow: Bool = false

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

// MARK: — Tests

@MainActor
final class TenantServerAnalyticsSinkTests: XCTestCase {

    private func makeSUT(
        batchSize: Int = 50,
        consent: AnalyticsConsentManager? = nil,
        session: AnalyticsSinkStub = AnalyticsSinkStub()
    ) -> (TenantServerAnalyticsSink, AnalyticsSinkStub) {
        let defaults = UserDefaults(suiteName: "test.sink.\(UUID().uuidString)")!
        let mgr = consent ?? AnalyticsConsentManager(defaults: defaults)
        mgr.optIn()
        let sink = TenantServerAnalyticsSink(
            endpoint: URL(string: "https://example.com/analytics/events")!,
            consentManager: mgr,
            session: session,
            batchSize: batchSize
        )
        return (sink, session)
    }

    private func makePayload(event: AnalyticsEvent = .appLaunched) -> AnalyticsEventPayload {
        AnalyticsEventPayload(
            event: event,
            timestamp: Date(),
            properties: [:],
            sessionId: UUID().uuidString,
            tenantSlug: "acme",
            appVersion: "1.0.0",
            platform: "iOS"
        )
    }

    // MARK: — Buffering before flush

    func test_enqueue_doesNotImmediatelySend_belowBatchSize() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        XCTAssertEqual(session.capturedRequests.count, 0,
            "Should not POST until batch threshold or flush")
    }

    // MARK: — Batch flush at threshold

    func test_enqueue_flushesWhenBatchSizeReached() async {
        let (sink, session) = makeSUT(batchSize: 3)
        for _ in 0..<3 {
            await sink.enqueue(makePayload())
        }
        // Allow async flush to complete
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.capturedRequests.count, 1, "Should POST once when batch reached")
    }

    // MARK: — Manual flush

    func test_flush_sendsBufferedEvents() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        await sink.enqueue(makePayload())
        await sink.flush()
        XCTAssertEqual(session.capturedRequests.count, 1, "flush() should POST buffered events")
    }

    func test_flush_withEmptyBuffer_doesNotPost() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.flush()
        XCTAssertEqual(session.capturedRequests.count, 0, "flush() on empty buffer should not POST")
    }

    // MARK: — Request shape

    func test_flush_postsCorrectURL() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        await sink.flush()
        XCTAssertEqual(session.capturedRequests.first?.url?.path, "/analytics/events")
    }

    func test_flush_postsJSON_contentType() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        await sink.flush()
        XCTAssertEqual(
            session.capturedRequests.first?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func test_flush_usesPostMethod() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        await sink.flush()
        XCTAssertEqual(session.capturedRequests.first?.httpMethod, "POST")
    }

    // MARK: — Fire-and-forget on failure

    func test_flush_dropsOnNetworkFailure_doesNotThrow() async {
        let session = AnalyticsSinkStub()
        session.shouldThrow = true
        let (sink, _) = makeSUT(batchSize: 50, session: session)
        await sink.enqueue(makePayload())
        // Should not crash / throw
        await sink.flush()
    }

    // MARK: — Consent gate

    func test_enqueue_whenOptedOut_doesNotBuffer() async {
        let defaults = UserDefaults(suiteName: "test.sink.consent.\(UUID().uuidString)")!
        let mgr = AnalyticsConsentManager(defaults: defaults)
        // leave opted-out (default)
        let session = AnalyticsSinkStub()
        let sink = TenantServerAnalyticsSink(
            endpoint: URL(string: "https://example.com/analytics/events")!,
            consentManager: mgr,
            session: session,
            batchSize: 1
        )
        await sink.enqueue(makePayload())
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(session.capturedRequests.count, 0,
            "Opted-out sink should drop events without network egress")
    }

    // MARK: — Buffer cleared after flush

    func test_flush_clearsBuffer() async {
        let (sink, session) = makeSUT(batchSize: 50)
        await sink.enqueue(makePayload())
        await sink.flush()
        await sink.flush() // second flush should be no-op
        XCTAssertEqual(session.capturedRequests.count, 1, "Buffer should be cleared after flush")
    }
}
