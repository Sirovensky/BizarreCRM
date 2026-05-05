import XCTest
@testable import Auth

/// §2 SessionTimer — timeout, touch, warning trigger, pause/resume.
///
/// Tests use a 10 ms poll interval so timer callbacks fire quickly at
/// the small (100–200 ms) idle timeouts we set here.
final class SessionTimerTests: XCTestCase {

    // MARK: - Timeout fires

    func test_timer_expiresAfterTimeout() async {
        let expectation = XCTestExpectation(description: "expire called")
        let timer = makeTimer(idleTimeout: 0.1) {
            expectation.fulfill()
        }
        await timer.start()
        await fulfillment(of: [expectation], timeout: 2.0)
        let running = await timer.isRunning
        XCTAssertFalse(running)
    }

    // MARK: - touch resets deadline

    func test_touch_preventsExpiry() async {
        let counter = Counter()
        let timer = makeTimer(idleTimeout: 0.15) {
            await counter.increment()
        }
        await timer.start()

        // Touch at 50 ms — well before expiry — resets the 150 ms window.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await timer.touch()

        // Wait 100 ms more (still < 150 ms since last touch).
        try? await Task.sleep(nanoseconds: 100_000_000)
        let count = await counter.value
        XCTAssertEqual(count, 0, "Timer should not have expired after touch")
    }

    // MARK: - currentRemaining

    func test_currentRemaining_isPositiveOnStart() async {
        let timer = makeTimer(idleTimeout: 10) { }
        await timer.start()
        let remaining = await timer.currentRemaining()
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThanOrEqual(remaining, 10)
    }

    func test_currentRemaining_returnsIdleTimeoutWhenPaused() async {
        let timer = makeTimer(idleTimeout: 30) { }
        await timer.start()
        await timer.pause()
        let remaining = await timer.currentRemaining()
        XCTAssertEqual(remaining, 30)
    }

    // MARK: - Warning trigger

    func test_warningFires_beforeExpiry() async {
        let warningExp = XCTestExpectation(description: "warning called")
        let expireExp  = XCTestExpectation(description: "expire called")

        // With idleTimeout=0.1 s: warning fires when remaining ≤ 20ms (80% elapsed).
        let timer = makeTimer(
            idleTimeout: 0.1,
            onWarning: { warningExp.fulfill() },
            onExpire:  { expireExp.fulfill() }
        )
        await timer.start()
        await fulfillment(of: [warningExp, expireExp], timeout: 3.0, enforceOrder: true)
    }

    func test_warningFires_onlyOncePerSession() async {
        let warningCounter = Counter()
        let expireExp = XCTestExpectation(description: "expire")
        let timer = makeTimer(
            idleTimeout: 0.1,
            onWarning: { await warningCounter.increment() },
            onExpire:  { expireExp.fulfill() }
        )
        await timer.start()
        await fulfillment(of: [expireExp], timeout: 3.0)
        let count = await warningCounter.value
        XCTAssertEqual(count, 1)
    }

    // MARK: - pause / resume

    func test_pausedTimer_doesNotExpire() async {
        let counter = Counter()
        let timer = makeTimer(idleTimeout: 0.05) {
            await counter.increment()
        }
        await timer.start()
        await timer.pause()
        let running = await timer.isRunning
        XCTAssertFalse(running)

        try? await Task.sleep(nanoseconds: 200_000_000) // 200 ms >> timeout
        let count = await counter.value
        XCTAssertEqual(count, 0)
    }

    func test_resume_afterPause_timerExpiresAgain() async {
        let expireExp = XCTestExpectation(description: "expire after resume")
        let timer = makeTimer(idleTimeout: 0.1) {
            expireExp.fulfill()
        }
        await timer.start()
        await timer.pause()
        await timer.resume()
        await fulfillment(of: [expireExp], timeout: 3.0)
    }

    func test_touchWhilePaused_isNoop() async {
        let timer = makeTimer(idleTimeout: 10) { }
        await timer.start()
        await timer.pause()
        await timer.touch() // should be no-op
        let running = await timer.isRunning
        XCTAssertFalse(running)
    }

    // MARK: - Factory

    private func makeTimer(
        idleTimeout: TimeInterval,
        onWarning: (@Sendable () async -> Void)? = nil,
        onExpire: @Sendable @escaping () async -> Void
    ) -> SessionTimer {
        SessionTimer(
            idleTimeout: idleTimeout,
            pollInterval: 0.01, // 10 ms — fast polling for tests
            onWarning: onWarning,
            onExpire: onExpire
        )
    }
}

// MARK: - Thread-safe counter

private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}
