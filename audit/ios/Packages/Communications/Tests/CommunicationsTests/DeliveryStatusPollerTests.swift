import XCTest
@testable import Communications
@testable import Networking

// MARK: - Mock

actor MockDeliveryAPIClient: APIClient {
    var responses: [DeliveryStatus] = []
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        callCount += 1
        let status = responses.isEmpty ? DeliveryStatus.sent : responses.removeFirst()
        let resp = DeliveryStatusResponse(messageId: 1, status: status, deliveredAt: nil, failureReason: nil, carrier: nil)
        guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    func set(_ r: [DeliveryStatus]) { responses = r }
}

// MARK: - Tests

@MainActor
final class DeliveryStatusPollerTests: XCTestCase {

    func test_initialStatus() {
        let api = MockDeliveryAPIClient()
        let poller = DeliveryStatusPoller(messageId: 1, api: api, pollInterval: 0.01, maxDuration: 0.1)
        XCTAssertEqual(poller.currentStatus, .sent)
        XCTAssertFalse(poller.isPolling)
    }

    func test_pollingStops_onTerminalDelivered() async throws {
        let api = MockDeliveryAPIClient()
        await api.set([.sent, .delivered])
        let poller = DeliveryStatusPoller(messageId: 1, api: api, pollInterval: 0.01, maxDuration: 1.0)

        await poller.startPolling()

        // Wait briefly for async polling to settle
        try await Task.sleep(for: .milliseconds(300))

        let count = await api.callCount
        XCTAssertGreaterThan(count, 0)
        XCTAssertEqual(poller.currentStatus, .delivered)
        XCTAssertFalse(poller.isPolling)
    }

    func test_pollingStops_onTerminalFailed() async throws {
        let api = MockDeliveryAPIClient()
        await api.set([.sent, .failed])
        let poller = DeliveryStatusPoller(messageId: 1, api: api, pollInterval: 0.01, maxDuration: 1.0)

        await poller.startPolling()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(poller.currentStatus, .failed)
        XCTAssertFalse(poller.isPolling)
    }

    func test_pollingStops_onTimeout() async throws {
        let api = MockDeliveryAPIClient()
        // Always returns .sent (non-terminal) — poller should stop after maxDuration
        let poller = DeliveryStatusPoller(messageId: 1, api: api, pollInterval: 0.02, maxDuration: 0.05)

        await poller.startPolling()
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertFalse(poller.isPolling)
    }

    func test_stopPolling_stopsEarly() async throws {
        let api = MockDeliveryAPIClient()
        let poller = DeliveryStatusPoller(messageId: 1, api: api, pollInterval: 0.5, maxDuration: 10.0)

        await poller.startPolling()
        XCTAssertTrue(poller.isPolling)
        poller.stopPolling()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(poller.isPolling)
    }
}
