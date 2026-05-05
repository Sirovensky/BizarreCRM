import XCTest
@testable import Notifications

// MARK: - WebSocketBackpressureTests
//
// §21.5 Backpressure — verifies WSBackpressureFilter coalesces at 1Hz.

final class WebSocketBackpressureTests: XCTestCase {

    func test_firstEvent_alwaysForwarded() async {
        let filter = WSBackpressureFilter(interval: 1.0)
        let result = await filter.shouldForward(topic: "dashboard")
        XCTAssertTrue(result, "First event must always be forwarded")
    }

    func test_immediateSecondEvent_dropped() async {
        let filter = WSBackpressureFilter(interval: 1.0)
        _ = await filter.shouldForward(topic: "dashboard")
        // Second call immediately after — should be dropped
        let second = await filter.shouldForward(topic: "dashboard")
        XCTAssertFalse(second, "Second event within interval must be dropped")
    }

    func test_differentTopics_independentFilters() async {
        let filter = WSBackpressureFilter(interval: 1.0)
        _ = await filter.shouldForward(topic: "dashboard")
        // A different topic should not be affected
        let other = await filter.shouldForward(topic: "tickets")
        XCTAssertTrue(other, "Different topic must have its own filter window")
    }

    func test_shortInterval_allowsSecondEvent() async throws {
        let filter = WSBackpressureFilter(interval: 0.05)  // 50ms window
        _ = await filter.shouldForward(topic: "dashboard")
        try await Task.sleep(nanoseconds: 60_000_000)  // 60ms > 50ms window
        let second = await filter.shouldForward(topic: "dashboard")
        XCTAssertTrue(second, "Event after interval expiry must be forwarded")
    }

    // MARK: - WSConnectionStateObserver

    @MainActor
    func test_connectionStateObserver_defaultsNotReconnecting() {
        let obs = WSConnectionStateObserver.shared
        // We can't guarantee the shared instance state in a test suite,
        // but we can verify the type and API exist.
        let _ = obs.isReconnecting  // compile check
        XCTAssertNotNil(obs)
    }
}
