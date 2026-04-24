import XCTest
@testable import Hardware

// MARK: - NetworkDrawerKickTests
//
// `NetworkDrawerKick` wraps a TCP send over OutputStream. Real TCP sends are
// not testable in unit tests without a live server, so this suite validates:
//   - Configuration storage and defaults.
//   - The `open()` path on an invalid host throws the expected `CashDrawerError`.
//   - The `open()` path with an empty host throws immediately.
//   - `isConnected` reflects the result of the last `open()` call.
//   - Error descriptions are populated.

final class NetworkDrawerKickTests: XCTestCase {

    // MARK: - Config defaults

    func test_config_defaultPort_is9100() {
        let config = NetworkDrawerKick.Config(host: "10.0.0.1")
        XCTAssertEqual(config.port, 9100)
    }

    func test_config_defaultTimeout_is5() {
        let config = NetworkDrawerKick.Config(host: "10.0.0.1")
        XCTAssertEqual(config.timeoutSeconds, 5.0, accuracy: 0.001)
    }

    func test_config_customPortAndTimeout() {
        let config = NetworkDrawerKick.Config(host: "192.168.1.5", port: 1234, timeoutSeconds: 3.0)
        XCTAssertEqual(config.host, "192.168.1.5")
        XCTAssertEqual(config.port, 1234)
        XCTAssertEqual(config.timeoutSeconds, 3.0, accuracy: 0.001)
    }

    // MARK: - isConnected initial state

    func test_isConnected_initiallyFalse() {
        let kick = NetworkDrawerKick(config: .init(host: "10.0.0.1"))
        XCTAssertFalse(kick.isConnected)
    }

    // MARK: - open() — empty host validation

    func test_open_emptyHost_throwsKickFailed() async {
        let kick = NetworkDrawerKick(config: .init(host: ""))
        do {
            try await kick.open()
            XCTFail("Expected CashDrawerError.kickFailed for empty host")
        } catch CashDrawerError.kickFailed {
            // expected — no host configured
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - open() — unreachable host fails within timeout

    func test_open_unreachableHost_throwsKickFailed() async {
        // Use 192.0.2.1 (RFC 5737 TEST-NET — guaranteed not reachable).
        // Use a very short timeout so the test completes quickly.
        let config = NetworkDrawerKick.Config(
            host: "192.0.2.1",
            port: 9100,
            timeoutSeconds: 0.5
        )
        let kick = NetworkDrawerKick(config: config)
        do {
            try await kick.open()
            XCTFail("Expected CashDrawerError.kickFailed for unreachable host")
        } catch CashDrawerError.kickFailed {
            // expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - isConnected after failed open()

    func test_isConnected_falseAfterFailedOpen() async {
        let kick = NetworkDrawerKick(config: .init(host: ""))
        _ = try? await kick.open()
        XCTAssertFalse(kick.isConnected,
                       "isConnected must remain false after a failed open()")
    }

    // MARK: - CashDrawer protocol conformance

    func test_conformsToCashDrawer() {
        let kick: CashDrawer = NetworkDrawerKick(config: .init(host: "10.0.0.1"))
        XCTAssertNotNil(kick)
    }

    // MARK: - Error descriptions

    func test_cashDrawerError_kickFailed_containsDetail() {
        let error = CashDrawerError.kickFailed("TCP timeout")
        XCTAssertTrue(error.errorDescription?.contains("TCP timeout") == true)
    }

    func test_cashDrawerError_notConnected_isNonEmpty() {
        XCTAssertFalse(CashDrawerError.notConnected.errorDescription?.isEmpty ?? true)
    }
}
