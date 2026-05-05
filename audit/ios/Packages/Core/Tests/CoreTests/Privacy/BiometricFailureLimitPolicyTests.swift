import XCTest
@testable import Core

// §28.10 — BiometricFailureLimitPolicy state machine tests

@MainActor
final class BiometricFailureLimitPolicyTests: XCTestCase {

    func test_initialState_isAllowedWithZeroFailures() {
        let policy = BiometricFailureLimitPolicy()
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 0))
        XCTAssertFalse(policy.requiresPasswordFallback)
        XCTAssertEqual(policy.consecutiveFailures, 0)
    }

    func test_recordFailure_underLimit_increments() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 3)
        policy.recordFailure()
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 1))
        policy.recordFailure()
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 2))
        XCTAssertFalse(policy.requiresPasswordFallback)
    }

    func test_recordFailure_atLimit_locksToFallback() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 3)
        policy.recordFailure()
        policy.recordFailure()
        policy.recordFailure()
        XCTAssertEqual(policy.state, .requiresPasswordFallback)
        XCTAssertTrue(policy.requiresPasswordFallback)
        XCTAssertEqual(policy.consecutiveFailures, 3)
    }

    func test_recordFailure_pastLimit_isIdempotent() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 2)
        policy.recordFailure()
        policy.recordFailure()
        policy.recordFailure() // extra
        policy.recordFailure() // extra
        XCTAssertEqual(policy.state, .requiresPasswordFallback)
    }

    func test_recordSuccess_resetsCounter() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 3)
        policy.recordFailure()
        policy.recordFailure()
        policy.recordSuccess()
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 0))
    }

    func test_reset_clearsLockedState() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 2)
        policy.recordFailure()
        policy.recordFailure()
        XCTAssertTrue(policy.requiresPasswordFallback)

        policy.reset()
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 0))
        XCTAssertFalse(policy.requiresPasswordFallback)
    }

    func test_customLimit_oneFailureLocksImmediately() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 1)
        policy.recordFailure()
        XCTAssertTrue(policy.requiresPasswordFallback)
    }

    func test_successAfterPartialFailures_lettsBiometryContinue() {
        let policy = BiometricFailureLimitPolicy(failureLimit: 3)
        policy.recordFailure()
        policy.recordFailure()
        policy.recordSuccess()
        // Two more failures should NOT lock — we reset to 0, so 2 < 3.
        policy.recordFailure()
        policy.recordFailure()
        XCTAssertFalse(policy.requiresPasswordFallback)
        XCTAssertEqual(policy.state, .allowed(consecutiveFailures: 2))
    }
}
