import Testing
import Foundation
@testable import KioskMode

// MARK: - KioskPINStorageTests

@Suite("KioskPINStorage — InMemory")
@MainActor
struct KioskPINStorageTests {

    private func makeStorage(pin: String? = nil) -> InMemoryKioskPINStorage {
        InMemoryKioskPINStorage(storedPIN: pin)
    }

    // MARK: - Enrollment

    @Test("Starts with no PIN enrolled")
    func startsNotEnrolled() {
        let storage = makeStorage()
        #expect(storage.isEnrolled == false)
    }

    @Test("isEnrolled is true after enrol")
    func enrollSetsEnrolled() throws {
        let storage = makeStorage()
        try storage.enrol(pin: "1234")
        #expect(storage.isEnrolled == true)
    }

    @Test("enrol replaces existing PIN")
    func enrollReplaces() throws {
        let storage = makeStorage(pin: "1234")
        try storage.enrol(pin: "5678")
        // New PIN should verify correctly
        #expect(storage.verify(pin: "5678") == .ok)
        #expect(storage.verify(pin: "1234") != .ok)
    }

    @Test("reset clears PIN and failure counter")
    func resetClearsPIN() throws {
        let storage = makeStorage(pin: "1234")
        storage.reset()
        #expect(storage.isEnrolled == false)
    }

    // MARK: - Verification — happy path

    @Test("verify returns .ok for correct PIN")
    func verifyOK() throws {
        let storage = makeStorage(pin: "4321")
        #expect(storage.verify(pin: "4321") == .ok)
    }

    @Test("verify returns .ok after multiple correct attempts")
    func verifyOKIdempotent() throws {
        let storage = makeStorage(pin: "9999")
        #expect(storage.verify(pin: "9999") == .ok)
        #expect(storage.verify(pin: "9999") == .ok)
    }

    // MARK: - Verification — wrong PIN

    @Test("verify returns .wrong on first failed attempt")
    func verifyWrongOnFirst() {
        let storage = makeStorage(pin: "1234")
        if case .wrong(let remaining) = storage.verify(pin: "0000") {
            #expect(remaining == 4) // 5 - 1 = 4 left
        } else {
            Issue.record("Expected .wrong result")
        }
    }

    @Test("verify .wrong remaining decreases with each failure")
    func verifyRemainingDecreases() {
        let storage = makeStorage(pin: "1234")
        _ = storage.verify(pin: "0000") // 1st fail
        _ = storage.verify(pin: "0000") // 2nd fail
        if case .wrong(let remaining) = storage.verify(pin: "0000") { // 3rd fail
            #expect(remaining == 2)
        } else {
            Issue.record("Expected .wrong result")
        }
    }

    @Test("verify resets failure counter on correct PIN")
    func verifyResetsCounterOnSuccess() {
        let storage = makeStorage(pin: "1234")
        _ = storage.verify(pin: "0000") // fail
        _ = storage.verify(pin: "0000") // fail
        #expect(storage.verify(pin: "1234") == .ok) // success → counter reset
        // Now should have full remaining again
        if case .wrong(let remaining) = storage.verify(pin: "0000") {
            #expect(remaining == 4)
        } else {
            Issue.record("Expected .wrong result")
        }
    }

    // MARK: - Lockout

    @Test("verify returns .lockedOut after 5 failures")
    func lockedOutAfterFiveFailures() {
        let storage = makeStorage(pin: "1234")
        for _ in 0..<5 { _ = storage.verify(pin: "0000") }
        if case .lockedOut = storage.verify(pin: "0000") {
            // pass
        } else {
            Issue.record("Expected .lockedOut result after 5 failures")
        }
    }

    // MARK: - Revocation

    @Test("verify returns .revoked after 10 failures")
    func revokedAfterTenFailures() {
        let storage = makeStorage(pin: "1234")
        for _ in 0..<10 { _ = storage.verify(pin: "0000") }
        #expect(storage.verify(pin: "1234") == .revoked)
        #expect(storage.isEnrolled == false)
    }

    @Test("verify with no enrolled PIN returns .revoked")
    func verifyWithNoPin() {
        let storage = makeStorage()
        #expect(storage.verify(pin: "1234") == .revoked)
    }
}

// MARK: - KioskActivationResultTests

@Suite("KioskActivationResult")
@MainActor
struct KioskActivationResultTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "test-activation-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    @Test("requestActivation with enrolled PIN activates immediately")
    func activatesWithEnrolledPin() throws {
        let manager = KioskModeManager(defaults: makeDefaults())
        let storage = InMemoryKioskPINStorage()
        try storage.enrol(pin: "1234")

        let result = manager.requestActivation(mode: .posOnly, pinStorage: storage)
        #expect(result == .activated)
        #expect(manager.currentMode == .posOnly)
    }

    @Test("requestActivation without enrolled PIN returns needsEnrollment")
    func needsEnrollmentWithNoPIN() {
        let manager = KioskModeManager(defaults: makeDefaults())
        let storage = InMemoryKioskPINStorage()

        let result = manager.requestActivation(mode: .clockInOnly, pinStorage: storage)
        #expect(result == .needsEnrollment(.clockInOnly))
        #expect(manager.currentMode == .off) // not activated yet
    }

    @Test("requestActivation .off always activates immediately")
    func offAlwaysActivates() {
        let manager = KioskModeManager(defaults: makeDefaults())
        let storage = InMemoryKioskPINStorage() // no PIN enrolled

        let result = manager.requestActivation(mode: .off, pinStorage: storage)
        #expect(result == .activated)
        #expect(manager.currentMode == .off)
    }

    @Test("requestActivation with enrolled PIN for training mode activates")
    func trainingActivatesWithPin() throws {
        let manager = KioskModeManager(defaults: makeDefaults())
        let storage = InMemoryKioskPINStorage()
        try storage.enrol(pin: "9876")

        let result = manager.requestActivation(mode: .training, pinStorage: storage)
        #expect(result == .activated)
        #expect(manager.currentMode == .training)
    }

    @Test("all active modes without PIN return needsEnrollment")
    func allModesNeedEnrollmentWithoutPin() {
        let activeModes: [KioskMode] = [.posOnly, .clockInOnly, .training]
        for mode in activeModes {
            let manager = KioskModeManager(defaults: makeDefaults())
            let storage = InMemoryKioskPINStorage()
            let result = manager.requestActivation(mode: mode, pinStorage: storage)
            #expect(result == .needsEnrollment(mode), "Mode \(mode) should need enrollment")
        }
    }
}

// MARK: - ManagerPinSheet logic tests

@Suite("ManagerPinSheet — PIN validation logic")
@MainActor
struct ManagerPinSheetLogicTests {

    @Test("correct PIN calls onSuccess")
    func correctPinCallsSuccess() {
        let storage = InMemoryKioskPINStorage(storedPIN: "5555")
        var successCalled = false
        _ = KioskPINVerifyResult.ok // anchor type

        let result = storage.verify(pin: "5555")
        if result == .ok { successCalled = true }
        #expect(successCalled == true)
    }

    @Test("incorrect PIN returns wrong result")
    func incorrectPinReturnsWrong() {
        let storage = InMemoryKioskPINStorage(storedPIN: "5555")
        let result = storage.verify(pin: "1111")
        if case .wrong = result {
            // expected
        } else {
            Issue.record("Expected .wrong, got \(result)")
        }
    }

    @Test("lockedOut result after 5 wrong attempts")
    func lockedOutAfterFiveAttempts() {
        let storage = InMemoryKioskPINStorage(storedPIN: "5555")
        for _ in 0..<5 { _ = storage.verify(pin: "0000") }
        let result = storage.verify(pin: "0000")
        if case .lockedOut(let until) = result {
            #expect(until > Date())
        } else {
            Issue.record("Expected .lockedOut, got \(result)")
        }
    }

    @Test("revoked result after 10 wrong attempts")
    func revokedAfterTenAttempts() {
        let storage = InMemoryKioskPINStorage(storedPIN: "5555")
        for _ in 0..<10 { _ = storage.verify(pin: "0000") }
        #expect(storage.verify(pin: "5555") == .revoked)
    }
}

// MARK: - KioskPINEnrollView logic tests

@Suite("KioskPINEnrollView — enrollment logic")
@MainActor
struct KioskPINEnrollLogicTests {

    @Test("enrol with valid PIN succeeds")
    func enrollValidPin() throws {
        let storage = InMemoryKioskPINStorage()
        try storage.enrol(pin: "4321")
        #expect(storage.isEnrolled == true)
        #expect(storage.verify(pin: "4321") == .ok)
    }

    @Test("enrol with different PIN fails subsequent verify")
    func enrollAndWrongVerify() throws {
        let storage = InMemoryKioskPINStorage()
        try storage.enrol(pin: "1111")
        if case .wrong = storage.verify(pin: "2222") {
            // expected
        } else {
            Issue.record("Expected .wrong for mismatched verify")
        }
    }

    @Test("re-enrol replaces previous PIN")
    func reEnrolReplaces() throws {
        let storage = InMemoryKioskPINStorage(storedPIN: "0000")
        try storage.enrol(pin: "7777")
        #expect(storage.verify(pin: "7777") == .ok)
        if case .wrong = storage.verify(pin: "0000") {
            // expected — old PIN gone
        } else {
            Issue.record("Old PIN should no longer work after re-enrol")
        }
    }
}
