import XCTest
@testable import Auth

// MARK: - PinLockoutPolicy tests

final class PinLockoutPolicyTests: XCTestCase {

    // MARK: - lockoutSeconds (static table)

    func test_lockoutSeconds_tier5_is30s() {
        XCTAssertEqual(PinLockoutPolicy.lockoutSeconds(for: 5), 30)
    }

    func test_lockoutSeconds_tier6_is5min() {
        XCTAssertEqual(PinLockoutPolicy.lockoutSeconds(for: 6), 5 * 60)
    }

    func test_lockoutSeconds_tier1to4_isNil() {
        for i in 1...4 {
            XCTAssertNil(PinLockoutPolicy.lockoutSeconds(for: i),
                         "No lockout expected at failure count \(i)")
        }
    }

    func test_lockoutSeconds_beyond6_isNil_becauseRevoked() {
        XCTAssertNil(PinLockoutPolicy.lockoutSeconds(for: 7))
        XCTAssertNil(PinLockoutPolicy.lockoutSeconds(for: 10))
    }

    // MARK: - initial state

    func test_state_allowedForNewUser() async {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        let state = await policy.state(for: 99)
        XCTAssertEqual(state, .allowed)
    }

    // MARK: - recordFailure escalation

    func test_recordFailure_1to4_staysAllowed() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        for _ in 1...4 {
            let state = try await policy.recordFailure(userId: 1)
            XCTAssertEqual(state, .allowed)
        }
    }

    func test_recordFailure_5th_locksFor30s() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        var state: LockoutState = .allowed
        for _ in 1...5 {
            state = try await policy.recordFailure(userId: 1)
        }
        guard case .locked(let until) = state else {
            return XCTFail("Expected .locked after 5 failures, got \(state)")
        }
        let diff = until.timeIntervalSinceNow
        XCTAssertGreaterThan(diff, 28, "Lockout should be ~30s in the future")
        XCTAssertLessThan(diff, 35)
    }

    func test_recordFailure_6th_locksFor5min() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        var state: LockoutState = .allowed
        for _ in 1...6 {
            state = try await policy.recordFailure(userId: 1)
        }
        guard case .locked(let until) = state else {
            return XCTFail("Expected .locked after 6 failures, got \(state)")
        }
        let diff = until.timeIntervalSinceNow
        XCTAssertGreaterThan(diff, 4 * 60 + 55, "Lockout should be ~5 min in the future")
        XCTAssertLessThan(diff, 5 * 60 + 5)
    }

    func test_recordFailure_7th_revokes() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        var state: LockoutState = .allowed
        for _ in 1...7 {
            state = try await policy.recordFailure(userId: 1)
        }
        XCTAssertEqual(state, .revoked)
    }

    func test_recordFailure_beyondMax_remainsRevoked() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        for _ in 1...8 {
            _ = try await policy.recordFailure(userId: 2)
        }
        let state = await policy.state(for: 2)
        XCTAssertEqual(state, .revoked)
    }

    // MARK: - state reflects stored record

    func test_state_lockedIfRecordHasFutureLockUntil() async {
        let storage = InMemoryLockoutStorage()
        let future = Date().addingTimeInterval(60)
        try? storage.save(LockoutRecord(userId: 5, failCount: 5, lockUntil: future))
        let policy = PinLockoutPolicy(storage: storage)
        let state = await policy.state(for: 5)
        guard case .locked = state else {
            return XCTFail("Expected .locked, got \(state)")
        }
    }

    func test_state_allowedIfLockUntilExpired() async {
        let storage = InMemoryLockoutStorage()
        let past = Date().addingTimeInterval(-10)
        try? storage.save(LockoutRecord(userId: 5, failCount: 5, lockUntil: past))
        let policy = PinLockoutPolicy(storage: storage)
        let state = await policy.state(for: 5)
        XCTAssertEqual(state, .allowed)
    }

    func test_state_revokedIfFailCountAtMax() async {
        let storage = InMemoryLockoutStorage()
        try? storage.save(LockoutRecord(userId: 5, failCount: PinLockoutPolicy.maxFailures))
        let policy = PinLockoutPolicy(storage: storage)
        let state = await policy.state(for: 5)
        XCTAssertEqual(state, .revoked)
    }

    // MARK: - recordSuccess

    func test_recordSuccess_clearsRecord() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        _ = try await policy.recordFailure(userId: 3)
        _ = try await policy.recordFailure(userId: 3)
        try await policy.recordSuccess(userId: 3)
        let state = await policy.state(for: 3)
        XCTAssertEqual(state, .allowed)
    }

    // MARK: - reset

    func test_reset_clearsRevokedRecord() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        for _ in 1...7 {
            _ = try await policy.recordFailure(userId: 9)
        }
        try await policy.reset(userId: 9)
        let state = await policy.state(for: 9)
        XCTAssertEqual(state, .allowed)
    }

    // MARK: - multiple users are independent

    func test_recordFailure_doesNotAffectOtherUsers() async throws {
        let policy = PinLockoutPolicy(storage: InMemoryLockoutStorage())
        for _ in 1...7 {
            _ = try await policy.recordFailure(userId: 10)
        }
        let stateUser20 = await policy.state(for: 20)
        XCTAssertEqual(stateUser20, .allowed)
    }
}
