import XCTest
@testable import Networking

// MARK: - RetryPolicyTests

final class RetryPolicyTests: XCTestCase {

    // MARK: Defaults

    func testDefaultPolicyValues() {
        let policy = RetryPolicy()
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 0.5)
        XCTAssertEqual(policy.maxDelay, 30)
        XCTAssertTrue(policy.jitter)
    }

    func testDefaultPreset() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertTrue(policy.jitter)
    }

    func testConservativePreset() {
        let policy = RetryPolicy.conservative
        XCTAssertEqual(policy.maxAttempts, 5)
        XCTAssertEqual(policy.baseDelay, 1)
        XCTAssertEqual(policy.maxDelay, 60)
    }

    func testNoRetryPreset() {
        let policy = RetryPolicy.noRetry
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    // MARK: Clamping

    func testMaxAttemptsClampedToOne() {
        let policy = RetryPolicy(maxAttempts: 0)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func testNegativeMaxAttemptsClamped() {
        let policy = RetryPolicy(maxAttempts: -5)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func testNegativeBaseDelayClampedToZero() {
        let policy = RetryPolicy(baseDelay: -1)
        XCTAssertEqual(policy.baseDelay, 0)
    }

    func testNegativeMaxDelayClampedToZero() {
        let policy = RetryPolicy(maxDelay: -10)
        XCTAssertEqual(policy.maxDelay, 0)
    }

    // MARK: Exponential delay schedule

    func testExponentialDelayAttemptZero() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: false)
        // attempt 0: 1 * 2^0 = 1
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 0), 1, accuracy: 0.0001)
    }

    func testExponentialDelayAttemptOne() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: false)
        // attempt 1: 1 * 2^1 = 2
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 1), 2, accuracy: 0.0001)
    }

    func testExponentialDelayAttemptTwo() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60, jitter: false)
        // attempt 2: 1 * 2^2 = 4
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 2), 4, accuracy: 0.0001)
    }

    func testExponentialDelayCapAtMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1, maxDelay: 5, jitter: false)
        // attempt 10: 1 * 2^10 = 1024, capped to 5
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 10), 5, accuracy: 0.0001)
    }

    func testExponentialDelayWithHalfSecondBase() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 30, jitter: false)
        // attempt 0: 0.5 * 1 = 0.5
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 0), 0.5, accuracy: 0.0001)
        // attempt 1: 0.5 * 2 = 1
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 1), 1, accuracy: 0.0001)
        // attempt 2: 0.5 * 4 = 2
        XCTAssertEqual(policy.exponentialDelay(forAttempt: 2), 2, accuracy: 0.0001)
    }

    // MARK: Equatable

    func testEqualPolicies() {
        let p1 = RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 30, jitter: false)
        let p2 = RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 30, jitter: false)
        XCTAssertEqual(p1, p2)
    }

    func testUnequalPolicies() {
        let p1 = RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 30, jitter: false)
        let p2 = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 30, jitter: false)
        XCTAssertNotEqual(p1, p2)
    }
}
