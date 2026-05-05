import XCTest
@testable import Core

// §28.8 — Unit tests for ScreenshotAuditCounter using the mock double

@MainActor
final class ScreenshotAuditCounterTests: XCTestCase {

    private var counter: MockScreenshotAuditCounter!

    override func setUp() {
        super.setUp()
        counter = MockScreenshotAuditCounter()
    }

    // MARK: - Initial state

    func test_initialCount_isZero() {
        XCTAssertEqual(counter.count, 0)
    }

    // MARK: - attach / simulateScreenshot

    func test_simulateScreenshot_incrementsCount() {
        counter.attach(screenIdentifier: "payment-receipt", userID: "u1") { _ in }
        counter.simulateScreenshot()
        XCTAssertEqual(counter.count, 1)
    }

    func test_simulateMultipleScreenshots_accumulatesCount() {
        counter.attach(screenIdentifier: "audit-export", userID: "u2") { _ in }
        counter.simulateScreenshot()
        counter.simulateScreenshot()
        counter.simulateScreenshot()
        XCTAssertEqual(counter.count, 3)
    }

    // MARK: - ScreenshotAuditEntry contents

    func test_entry_hasCorrectScreenIdentifier() {
        var received: ScreenshotAuditEntry?
        counter.attach(screenIdentifier: "2fa-backup-codes", userID: "u3") { entry in
            received = entry
        }
        counter.simulateScreenshot()
        XCTAssertEqual(received?.screenIdentifier, "2fa-backup-codes")
    }

    func test_entry_hasCorrectUserID() {
        var received: ScreenshotAuditEntry?
        counter.attach(screenIdentifier: "payment", userID: "user42") { entry in
            received = entry
        }
        counter.simulateScreenshot()
        XCTAssertEqual(received?.userID, "user42")
    }

    func test_entry_hasCorrectTimestamp() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        var received: ScreenshotAuditEntry?
        counter.attach(screenIdentifier: "screen", userID: nil) { entry in
            received = entry
        }
        counter.simulateScreenshot(at: fixedDate)
        XCTAssertEqual(received?.timestamp, fixedDate)
    }

    func test_entry_nilUserID_whenNotAuthenticated() {
        var received: ScreenshotAuditEntry?
        counter.attach(screenIdentifier: "pre-auth", userID: nil) { entry in
            received = entry
        }
        counter.simulateScreenshot()
        XCTAssertNil(received?.userID)
    }

    // MARK: - capturedEntries

    func test_capturedEntries_collectsAllEntries() {
        counter.attach(screenIdentifier: "screen", userID: "u1") { _ in }
        counter.simulateScreenshot()
        counter.simulateScreenshot()
        XCTAssertEqual(counter.capturedEntries.count, 2)
    }

    // MARK: - detach

    func test_detach_preventsHandlerCallsAfterDetach() {
        var callCount = 0
        counter.attach(screenIdentifier: "screen", userID: nil) { _ in callCount += 1 }
        counter.simulateScreenshot()   // count = 1
        counter.detach()
        // After detach, handler is nil — simulateScreenshot increments count
        // but should not call handler or add to capturedEntries.
        counter.simulateScreenshot()   // count increments but no handler
        XCTAssertEqual(callCount, 1, "Handler must not be called after detach")
    }

    // MARK: - re-attach resets count

    func test_reattach_resetsCount() {
        counter.attach(screenIdentifier: "s1", userID: nil) { _ in }
        counter.simulateScreenshot()
        counter.simulateScreenshot()
        XCTAssertEqual(counter.count, 2)

        counter.attach(screenIdentifier: "s2", userID: nil) { _ in }
        XCTAssertEqual(counter.count, 0, "Reattach must reset count to 0")
    }

    // MARK: - ScreenshotAuditEntry Equatable

    func test_auditEntry_equatable() {
        let date = Date(timeIntervalSince1970: 1_000)
        let a = ScreenshotAuditEntry(screenIdentifier: "s", timestamp: date, userID: "u")
        let b = ScreenshotAuditEntry(screenIdentifier: "s", timestamp: date, userID: "u")
        XCTAssertEqual(a, b)
    }
}
