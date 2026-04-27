import XCTest
@testable import Notifications

// MARK: - §21.3 SilentPushCoalescer tests

final class SilentPushCoalescerTests: XCTestCase {

    // MARK: - Debounce

    func test_singleArrive_firesAfterDebounce() async {
        var firedCount = 0
        var firedWith = 0
        let coalescer = SilentPushCoalescer(debounceInterval: 0.05, maxCoalesceCount: 100) { count in
            firedCount += 1
            firedWith = count
        }

        await coalescer.arrive()
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms > 50ms debounce

        XCTAssertEqual(firedCount, 1)
        XCTAssertEqual(firedWith, 1)
    }

    func test_multipleArrivesWithinWindow_coalesceToSingleFire() async {
        var firedCount = 0
        var coalescedCount = 0
        let coalescer = SilentPushCoalescer(debounceInterval: 0.1, maxCoalesceCount: 100) { count in
            firedCount += 1
            coalescedCount = count
        }

        await coalescer.arrive()
        await coalescer.arrive()
        await coalescer.arrive()
        try? await Task.sleep(nanoseconds: 250_000_000) // 250ms > 100ms debounce

        XCTAssertEqual(firedCount, 1, "Should coalesce into a single fire")
        XCTAssertEqual(coalescedCount, 3, "Should report count of 3 coalesced pushes")
    }

    // MARK: - High-water

    func test_highWaterReached_firesImmediately() async throws {
        var firedCount = 0
        var firedWith = 0
        let maxCoalesce = 5
        let coalescer = SilentPushCoalescer(
            debounceInterval: 10.0, // Very long — should never fire via debounce in test
            maxCoalesceCount: maxCoalesce
        ) { count in
            firedCount += 1
            firedWith = count
        }

        // Send exactly maxCoalesce arrivals — should trigger immediate fire.
        for _ in 0..<maxCoalesce {
            await coalescer.arrive()
        }
        // Small yield to let the Task in fireDirect() run.
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(firedCount, 1, "High-water should fire once")
        XCTAssertEqual(firedWith, maxCoalesce)
    }

    // MARK: - Backoff helper (PushTokenRetryService)

    func test_backoffDelay_increasesExponentially() {
        let d0 = PushTokenRetryService.backoffDelay(attempt: 0)
        let d1 = PushTokenRetryService.backoffDelay(attempt: 1)
        let d2 = PushTokenRetryService.backoffDelay(attempt: 2)
        XCTAssertLessThan(d0, d1)
        XCTAssertLessThan(d1, d2)
    }

    func test_backoffDelay_cappedAtMaxDelay() {
        let d = PushTokenRetryService.backoffDelay(attempt: 100) // Very large attempt
        XCTAssertLessThanOrEqual(d, PushTokenRetryService.maxDelay * 1.15) // allow jitter
    }
}
