import XCTest
import LocalAuthentication
@testable import Auth

// MARK: - BiometricAuthServiceTests

/// §2 — State-machine tests for `BiometricAuthService`.
///
/// Coverage:
/// - `checkAvailability()` → `.available` / `.unavailable` states
/// - `evaluate(reason:)` → success, user-cancel, locked-out, permission-denied,
///   generic-error, and not-available transitions
/// - LAContext call counts (canEvaluate is called once per evaluate())
@MainActor
final class BiometricAuthServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        canEvaluate: Bool = false,
        canEvaluateError: Error? = nil,
        biometryType: LABiometryType = .none,
        evaluateResult: Result<Bool, Error> = .success(false)
    ) -> (BiometricAuthService, MockLAContext) {
        let mock = MockLAContext()
        mock.canEvaluateResult = (canEvaluate, canEvaluateError)
        mock.stubbedBiometryType = biometryType
        mock.evaluateResult = evaluateResult
        let svc = BiometricAuthService(context: mock)
        return (svc, mock)
    }

    private func laError(_ code: LAError.Code) -> LAError {
        LAError(code)
    }

    // MARK: - checkAvailability

    func test_checkAvailability_whenCanEvaluateTrue_faceID_returnsAvailable() {
        let (svc, _) = makeService(canEvaluate: true, biometryType: .faceID)
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .available(kind: .faceID))
    }

    func test_checkAvailability_whenCanEvaluateTrue_touchID_returnsAvailable() {
        let (svc, _) = makeService(canEvaluate: true, biometryType: .touchID)
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .available(kind: .touchID))
    }

    func test_checkAvailability_whenCanEvaluateTrue_opticID_returnsAvailable() {
        let (svc, _) = makeService(canEvaluate: true, biometryType: .opticID)
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .available(kind: .opticID))
    }

    func test_checkAvailability_whenCanEvaluateFalse_notEnrolled_returnsUnavailable() {
        let (svc, _) = makeService(
            canEvaluate: false,
            canEvaluateError: laError(.biometryNotEnrolled)
        )
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .unavailable(reason: .notAvailable))
    }

    func test_checkAvailability_whenCanEvaluateFalse_notAvailable_returnsUnavailable() {
        let (svc, _) = makeService(
            canEvaluate: false,
            canEvaluateError: laError(.biometryNotAvailable)
        )
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .unavailable(reason: .notAvailable))
    }

    func test_checkAvailability_whenCanEvaluateFalse_lockout_returnsLockedOut() {
        let (svc, _) = makeService(
            canEvaluate: false,
            canEvaluateError: laError(.biometryLockout)
        )
        let result = svc.checkAvailability()
        XCTAssertEqual(result, .unavailable(reason: .lockedOut))
    }

    func test_checkAvailability_cachesMostRecentResult() {
        let (svc, mock) = makeService(canEvaluate: true, biometryType: .faceID)
        _ = svc.checkAvailability()
        _ = svc.checkAvailability()
        // Mock records every call; both checks should have gone through
        XCTAssertEqual(mock.canEvaluateCallCount, 2)
        XCTAssertEqual(svc.availability, .available(kind: .faceID))
    }

    func test_checkAvailability_initialState_isUnknown() {
        let mock = MockLAContext()
        let svc = BiometricAuthService(context: mock)
        XCTAssertEqual(svc.availability, .unknown)
    }

    // MARK: - evaluate — happy path

    func test_evaluate_success_returnsTrue() async throws {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .success(true)
        )
        let result = try await svc.evaluate(reason: "Test unlock")
        XCTAssertTrue(result)
    }

    func test_evaluate_passesThroughReason() async throws {
        let (svc, mock) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .success(true)
        )
        _ = try await svc.evaluate(reason: "Unlock CRM")
        XCTAssertEqual(mock.lastEvaluateReason, "Unlock CRM")
    }

    func test_evaluate_callsCanEvaluateOnEachCall() async throws {
        let (svc, mock) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .success(true)
        )
        _ = try await svc.evaluate(reason: "r1")
        _ = try await svc.evaluate(reason: "r2")
        XCTAssertEqual(mock.canEvaluateCallCount, 2)
        XCTAssertEqual(mock.evaluateCallCount, 2)
    }

    // MARK: - evaluate — not available path

    func test_evaluate_whenUnavailable_throwsNotAvailable() async {
        let (svc, _) = makeService(
            canEvaluate: false,
            canEvaluateError: laError(.biometryNotAvailable)
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.notAvailable")
        } catch BiometricAuthError.notAvailable {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_evaluate_whenNotAvailable_doesNotCallEvaluate() async {
        let (svc, mock) = makeService(canEvaluate: false)
        _ = try? await svc.evaluate(reason: "r")
        XCTAssertEqual(mock.evaluateCallCount, 0)
    }

    // MARK: - evaluate — user-cancel transitions

    func test_evaluate_userCancel_throwsUserCancelled() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.userCancel))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.userCancelled")
        } catch BiometricAuthError.userCancelled {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_evaluate_appCancel_throwsUserCancelled() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.appCancel))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.userCancelled")
        } catch BiometricAuthError.userCancelled {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_evaluate_userFallback_throwsUserCancelled() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.userFallback))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.userCancelled")
        } catch BiometricAuthError.userCancelled {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_evaluate_systemCancel_throwsUserCancelled() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.systemCancel))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.userCancelled")
        } catch BiometricAuthError.userCancelled {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - evaluate — locked-out transition

    func test_evaluate_biometryLockout_throwsLockedOut() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.biometryLockout))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.lockedOut")
        } catch BiometricAuthError.lockedOut {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - evaluate — generic / unknown errors

    func test_evaluate_unknownLAError_throwsUnderlyingError() async {
        let (svc, _) = makeService(
            canEvaluate: true,
            biometryType: .faceID,
            evaluateResult: .failure(laError(.invalidContext))
        )
        do {
            _ = try await svc.evaluate(reason: "r")
            XCTFail("Expected BiometricAuthError.underlyingError")
        } catch BiometricAuthError.underlyingError {
            // expected — code is device-dependent, just confirm the case
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - availability state updates

    func test_availability_updatesAfterCheckAvailability_toAvailable() {
        let (svc, _) = makeService(canEvaluate: true, biometryType: .touchID)
        XCTAssertEqual(svc.availability, .unknown)
        svc.checkAvailability()
        XCTAssertEqual(svc.availability, .available(kind: .touchID))
    }

    func test_availability_updatesAfterCheckAvailability_toUnavailable() {
        let (svc, _) = makeService(
            canEvaluate: false,
            canEvaluateError: laError(.biometryNotEnrolled)
        )
        svc.checkAvailability()
        XCTAssertEqual(svc.availability, .unavailable(reason: .notAvailable))
    }
}

// MARK: - LastUsernameStoreTests

/// Unit tests for `LastUsernameStore` using `InMemoryUsernameStorage`.
final class LastUsernameStoreTests: XCTestCase {

    private func makeStore() -> LastUsernameStore {
        LastUsernameStore(storage: InMemoryUsernameStorage())
    }

    func test_lastUsername_nilWhenNothingStored() async {
        let store = makeStore()
        let result = await store.lastUsername()
        XCTAssertNil(result)
    }

    func test_save_and_load_roundTrip() async throws {
        let store = makeStore()
        try await store.save(username: "alice@example.com")
        let loaded = await store.lastUsername()
        XCTAssertEqual(loaded, "alice@example.com")
    }

    func test_save_trimsWhitespace() async throws {
        let store = makeStore()
        try await store.save(username: "  bob@example.com  ")
        let loaded = await store.lastUsername()
        XCTAssertEqual(loaded, "bob@example.com")
    }

    func test_save_emptyString_throws() async {
        let store = makeStore()
        do {
            try await store.save(username: "")
            XCTFail("Expected LastUsernameStoreError.emptyUsername")
        } catch LastUsernameStoreError.emptyUsername {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_save_whitespaceOnly_throws() async {
        let store = makeStore()
        do {
            try await store.save(username: "   ")
            XCTFail("Expected LastUsernameStoreError.emptyUsername")
        } catch LastUsernameStoreError.emptyUsername {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_save_overwritesPreviousUsername() async throws {
        let store = makeStore()
        try await store.save(username: "first@example.com")
        try await store.save(username: "second@example.com")
        let loaded = await store.lastUsername()
        XCTAssertEqual(loaded, "second@example.com")
    }

    func test_clear_removesUsername() async throws {
        let store = makeStore()
        try await store.save(username: "user@example.com")
        try await store.clear()
        let loaded = await store.lastUsername()
        XCTAssertNil(loaded)
    }

    func test_clear_whenNothingStored_doesNotThrow() async {
        let store = makeStore()
        do {
            try await store.clear()
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }
}

// MARK: - BiometricCredentialStoreTests

/// Unit tests for `BiometricCredentialStore` using `InMemoryPasswordStorage`.
final class BiometricCredentialStoreTests: XCTestCase {

    private func makeStore() -> BiometricCredentialStore {
        BiometricCredentialStore(storage: InMemoryPasswordStorage())
    }

    func test_loadPassword_nilWhenNothingStored() async throws {
        let store = makeStore()
        let loaded = try await store.loadPassword()
        XCTAssertNil(loaded)
    }

    func test_saveAndLoad_roundTrip() async throws {
        let store = makeStore()
        try await store.savePassword("s3cur3Pa$$")
        let loaded = try await store.loadPassword()
        XCTAssertEqual(loaded, "s3cur3Pa$$")
    }

    func test_save_emptyPassword_throws() async {
        let store = makeStore()
        do {
            try await store.savePassword("")
            XCTFail("Expected BiometricCredentialStoreError.emptyPassword")
        } catch BiometricCredentialStoreError.emptyPassword {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_save_whitespaceOnly_throws() async {
        let store = makeStore()
        do {
            try await store.savePassword("   ")
            XCTFail("Expected BiometricCredentialStoreError.emptyPassword")
        } catch BiometricCredentialStoreError.emptyPassword {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_save_overwritesPreviousPassword() async throws {
        let store = makeStore()
        try await store.savePassword("old_pass")
        try await store.savePassword("new_pass")
        let loaded = try await store.loadPassword()
        XCTAssertEqual(loaded, "new_pass")
    }

    func test_clear_removesPassword() async throws {
        let store = makeStore()
        try await store.savePassword("p@ssword")
        try await store.clear()
        let loaded = try await store.loadPassword()
        XCTAssertNil(loaded)
    }

    func test_clear_whenNothingStored_doesNotThrow() async {
        let store = makeStore()
        do {
            try await store.clear()
        } catch {
            XCTFail("Unexpected throw: \(error)")
        }
    }

    func test_hasStoredPassword_falseWhenEmpty() async {
        let store = makeStore()
        let has = await store.hasStoredPassword
        XCTAssertFalse(has)
    }

    func test_hasStoredPassword_trueAfterSave() async throws {
        let store = makeStore()
        try await store.savePassword("password123")
        let has = await store.hasStoredPassword
        XCTAssertTrue(has)
    }

    func test_hasStoredPassword_falseAfterClear() async throws {
        let store = makeStore()
        try await store.savePassword("password123")
        try await store.clear()
        let has = await store.hasStoredPassword
        XCTAssertFalse(has)
    }
}
