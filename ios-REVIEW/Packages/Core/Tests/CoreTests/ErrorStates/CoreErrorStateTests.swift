import XCTest
@testable import Core

// §63 — Unit tests for CoreErrorState enum cases and computed properties.

final class CoreErrorStateTests: XCTestCase {

    // MARK: — symbolName

    func testSymbolName_network() {
        XCTAssertEqual(CoreErrorState.network.symbolName, "wifi.exclamationmark")
    }

    func testSymbolName_server() {
        XCTAssertEqual(CoreErrorState.server(status: 503, message: nil).symbolName, "server.rack")
    }

    func testSymbolName_unauthorized() {
        XCTAssertEqual(CoreErrorState.unauthorized.symbolName, "lock.fill")
    }

    func testSymbolName_forbidden() {
        XCTAssertEqual(CoreErrorState.forbidden.symbolName, "lock.slash.fill")
    }

    func testSymbolName_notFound() {
        XCTAssertEqual(CoreErrorState.notFound.symbolName, "questionmark.folder")
    }

    func testSymbolName_offline() {
        XCTAssertEqual(CoreErrorState.offline.symbolName, "wifi.slash")
    }

    func testSymbolName_validation() {
        XCTAssertEqual(CoreErrorState.validation(["email"]).symbolName, "exclamationmark.triangle.fill")
    }

    func testSymbolName_rateLimited() {
        XCTAssertEqual(CoreErrorState.rateLimited(retrySeconds: 5).symbolName, "clock.badge.exclamationmark")
    }

    func testSymbolName_unknown() {
        XCTAssertEqual(CoreErrorState.unknown.symbolName, "exclamationmark.circle")
    }

    // MARK: — title

    func testTitle_eachCase() {
        let cases: [(CoreErrorState, String)] = [
            (.network, "Connection Problem"),
            (.server(status: 500, message: nil), "Server Error"),
            (.unauthorized, "Session Expired"),
            (.forbidden, "Access Denied"),
            (.notFound, "Not Found"),
            (.offline, "You're Offline"),
            (.validation([]), "Check Your Input"),
            (.rateLimited(retrySeconds: nil), "Too Many Requests"),
            (.unknown, "Something Went Wrong")
        ]
        for (state, expected) in cases {
            XCTAssertEqual(state.title, expected, "Title mismatch for \(state)")
        }
    }

    // MARK: — message

    func testMessage_network() {
        let msg = CoreErrorState.network.message
        XCTAssertFalse(msg.isEmpty)
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("network") ||
                      msg.localizedCaseInsensitiveContains("connection"))
    }

    func testMessage_server_withServerMessage() {
        let state = CoreErrorState.server(status: 503, message: "Unavailable")
        XCTAssertEqual(state.message, "Unavailable")
    }

    func testMessage_server_withoutServerMessage() {
        let state = CoreErrorState.server(status: 500, message: nil)
        XCTAssertTrue(state.message.contains("500"))
    }

    func testMessage_rateLimited_withSeconds() {
        let state = CoreErrorState.rateLimited(retrySeconds: 1)
        XCTAssertTrue(state.message.contains("1 second"))
    }

    func testMessage_rateLimited_pluralSeconds() {
        let state = CoreErrorState.rateLimited(retrySeconds: 30)
        XCTAssertTrue(state.message.contains("30 seconds"))
    }

    func testMessage_rateLimited_nil() {
        let state = CoreErrorState.rateLimited(retrySeconds: nil)
        XCTAssertFalse(state.message.isEmpty)
    }

    func testMessage_validation_empty() {
        let state = CoreErrorState.validation([])
        XCTAssertFalse(state.message.isEmpty)
    }

    func testMessage_validation_withFields() {
        let state = CoreErrorState.validation(["email", "phone"])
        XCTAssertTrue(state.message.contains("email"))
    }

    func testMessage_validation_clampsToThreeFields() {
        let fields = ["a", "b", "c", "d", "e"]
        let msg = CoreErrorState.validation(fields).message
        // At most 3 shown — "d" and "e" must not appear
        XCTAssertFalse(msg.contains("d"))
        XCTAssertFalse(msg.contains("e"))
    }

    // MARK: — isRetryable

    func testIsRetryable_retryableCases() {
        let retryable: [CoreErrorState] = [
            .network,
            .server(status: 500, message: nil),
            .offline,
            .rateLimited(retrySeconds: nil),
            .unknown,
            .unauthorized   // "Sign In" CTA is a primary action
        ]
        for state in retryable {
            XCTAssertTrue(state.isRetryable, "\(state) should be retryable")
        }
    }

    func testIsRetryable_nonRetryableCases() {
        let nonRetryable: [CoreErrorState] = [
            .forbidden,
            .notFound,
            .validation([])
        ]
        for state in nonRetryable {
            XCTAssertFalse(state.isRetryable, "\(state) should NOT be retryable")
        }
    }

    // MARK: — retryLabel

    func testRetryLabel_unauthorized() {
        XCTAssertEqual(CoreErrorState.unauthorized.retryLabel, "Sign In")
    }

    func testRetryLabel_network() {
        XCTAssertEqual(CoreErrorState.network.retryLabel, "Try Again")
    }

    func testRetryLabel_unknown() {
        XCTAssertEqual(CoreErrorState.unknown.retryLabel, "Try Again")
    }

    // MARK: — Equatable

    func testEquatable_sameCase() {
        XCTAssertEqual(CoreErrorState.network, .network)
        XCTAssertEqual(CoreErrorState.offline, .offline)
        XCTAssertEqual(
            CoreErrorState.server(status: 500, message: "msg"),
            CoreErrorState.server(status: 500, message: "msg")
        )
    }

    func testEquatable_differentCases() {
        XCTAssertNotEqual(CoreErrorState.network, .offline)
        XCTAssertNotEqual(
            CoreErrorState.server(status: 500, message: nil),
            CoreErrorState.server(status: 503, message: nil)
        )
    }

    func testEquatable_validation_differentFields() {
        XCTAssertNotEqual(
            CoreErrorState.validation(["a"]),
            CoreErrorState.validation(["b"])
        )
    }

    func testEquatable_rateLimited_differentSeconds() {
        XCTAssertNotEqual(
            CoreErrorState.rateLimited(retrySeconds: 10),
            CoreErrorState.rateLimited(retrySeconds: 20)
        )
    }
}
