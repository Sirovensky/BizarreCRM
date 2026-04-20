import XCTest
@testable import Persistence

@MainActor
final class PINStoreTests: XCTestCase {
    override func setUp() async throws {
        PINStore.shared.reset()
    }

    override func tearDown() async throws {
        PINStore.shared.reset()
    }

    // MARK: - Enrollment + happy-path verify

    func test_enrolAndVerify_ok() throws {
        try PINStore.shared.enrol(pin: "1234")
        XCTAssertTrue(PINStore.shared.isEnrolled)
        XCTAssertEqual(PINStore.shared.verify(pin: "1234"), .ok)
    }

    func test_correctPINResetsFailCounter() throws {
        try PINStore.shared.enrol(pin: "1234")
        _ = PINStore.shared.verify(pin: "0000")  // 1
        _ = PINStore.shared.verify(pin: "0000")  // 2
        XCTAssertEqual(PINStore.shared.failCount, 2)
        XCTAssertEqual(PINStore.shared.verify(pin: "1234"), .ok)
        XCTAssertEqual(PINStore.shared.failCount, 0)
    }

    // MARK: - Wrong-PIN escalation

    func test_wrongPIN_belowLockoutGate_reportsRemainingTries() throws {
        try PINStore.shared.enrol(pin: "1234")
        if case let .wrong(remaining) = PINStore.shared.verify(pin: "0000") {
            XCTAssertEqual(remaining, 4) // 5 allowed, 1 used → 4 left
        } else {
            XCTFail("Expected .wrong")
        }
    }

    func test_fifthFailure_triggers30sLockout() throws {
        try PINStore.shared.enrol(pin: "1234")
        for _ in 0..<4 { _ = PINStore.shared.verify(pin: "0000") }
        let result = PINStore.shared.verify(pin: "0000") // 5th
        guard case let .lockedOut(until) = result else {
            XCTFail("Expected .lockedOut, got \(result)")
            return
        }
        let delay = until.timeIntervalSinceNow
        XCTAssertGreaterThan(delay, 25)
        XCTAssertLessThan(delay, 31)
    }

    func test_sixthFailure_extendsLockout() throws {
        try PINStore.shared.enrol(pin: "1234")
        // Burn 5 attempts to land in the 30s tier.
        for _ in 0..<5 { _ = PINStore.shared.verify(pin: "0000") }
        // Expire the lockout artificially by resetting lockUntil only.
        try? KeychainStore.shared.remove(.pinLockUntil)
        // 6th failure should mount the 60s tier.
        if case let .lockedOut(until) = PINStore.shared.verify(pin: "0000") {
            let delay = until.timeIntervalSinceNow
            XCTAssertGreaterThan(delay, 55)
            XCTAssertLessThan(delay, 61)
        } else {
            XCTFail("Expected .lockedOut at tier 6")
        }
    }

    func test_tenthFailure_marksRevoked_andClearsStoredPIN() throws {
        try PINStore.shared.enrol(pin: "1234")
        for failIdx in 1..<10 {
            _ = PINStore.shared.verify(pin: "0000")
            if PINStore.shared.lockoutEndsAt != nil {
                // Skip over active lockouts in the test so we can keep counting.
                try? KeychainStore.shared.remove(.pinLockUntil)
            }
            _ = failIdx
        }
        // 10th failure → revoked.
        XCTAssertEqual(PINStore.shared.verify(pin: "0000"), .revoked)
        XCTAssertFalse(PINStore.shared.isEnrolled)
    }

    func test_lockoutTierSecondsMatchSpec() {
        XCTAssertNil(PINStore.lockoutSeconds(for: 4))
        XCTAssertEqual(PINStore.lockoutSeconds(for: 5), 30)
        XCTAssertEqual(PINStore.lockoutSeconds(for: 6), 60)
        XCTAssertEqual(PINStore.lockoutSeconds(for: 7), 300)
        XCTAssertEqual(PINStore.lockoutSeconds(for: 8), 900)
        XCTAssertEqual(PINStore.lockoutSeconds(for: 9), 3600)
    }

    // MARK: - Lockout persistence

    func test_verifyDuringActiveLockout_stillReportsLocked_withoutIncrementing() throws {
        try PINStore.shared.enrol(pin: "1234")
        for _ in 0..<5 { _ = PINStore.shared.verify(pin: "0000") }
        let priorCount = PINStore.shared.failCount
        // Attempt during lockout.
        if case .lockedOut = PINStore.shared.verify(pin: "1234") {
            // Even a correct PIN during lockout should be rejected; counter
            // does NOT increment further.
            XCTAssertEqual(PINStore.shared.failCount, priorCount)
        } else {
            XCTFail("Expected .lockedOut")
        }
    }
}
