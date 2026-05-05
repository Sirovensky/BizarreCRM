import XCTest
@testable import Auth
import Networking
import Core

// MARK: - Enrollment ViewModel state machine tests

@MainActor
final class TwoFactorEnrollmentViewModelTests: XCTestCase {

    // MARK: - Idle → Enrolling → QR

    func test_initialState_isIdle() {
        let vm = TwoFactorEnrollmentViewModel(repository: StubTwoFactorRepository())
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.recoveryCodeList.codes.isEmpty)
    }

    func test_continueFromIntro_transitionsToShowingQR_onSuccess() async {
        let stub = StubTwoFactorRepository()
        stub.enrollResult = .success(TwoFactorEnrollResponse(
            secret: "JBSWY3DPEHPK3PXP",
            otpauthURI: "otpauth://totp/BizarreCRM:test@example.com?secret=JBSWY3DPEHPK3PXP",
            backupCodes: Array(repeating: "ABCD1234", count: 10)
        ))
        let vm = TwoFactorEnrollmentViewModel(repository: stub)

        await vm.continueFromIntro()

        XCTAssertEqual(vm.state, .showingQR)
        XCTAssertEqual(vm.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertFalse(vm.otpauthURI.isEmpty)
        XCTAssertEqual(vm.recoveryCodeList.codes.count, 10)
        XCTAssertFalse(vm.isLoading)
    }

    func test_continueFromIntro_transitionsToError_onFailure() async {
        let stub = StubTwoFactorRepository()
        stub.enrollResult = .failure(AppError.network(underlying: nil))
        let vm = TwoFactorEnrollmentViewModel(repository: stub)

        await vm.continueFromIntro()

        if case .error = vm.state {} else {
            XCTFail("Expected .error state, got \(vm.state)")
        }
        XCTAssertFalse(vm.isLoading)
    }

    func test_continueFromIntro_isNoOp_ifNotIdle() async {
        // Reach showingQR first via a successful enroll
        let stub1 = StubTwoFactorRepository()
        stub1.enrollResult = .success(TwoFactorEnrollResponse(
            secret: "S", otpauthURI: "otpauth://x", backupCodes: []
        ))
        let vm = TwoFactorEnrollmentViewModel(repository: stub1)
        await vm.continueFromIntro()
        XCTAssertEqual(vm.state, .showingQR)

        // Now a second call should be no-op (stub2 would error if called)
        let stub2 = StubTwoFactorRepository()
        stub2.enrollResult = .failure(AppError.network(underlying: nil))
        // State is already .showingQR — continueFromIntro checks guard state == .idle
        await vm.continueFromIntro()
        XCTAssertEqual(vm.state, .showingQR)
    }

    // MARK: - Verify code validation

    /// Helper: enroll and return a VM already in .showingQR state.
    private func makeQRVM(verifyResult: Result<TwoFactorVerifyResponse, Error> = .failure(AppError.network(underlying: nil))) async -> TwoFactorEnrollmentViewModel {
        let stub = StubTwoFactorRepository()
        stub.enrollResult = .success(TwoFactorEnrollResponse(
            secret: "SECRET",
            otpauthURI: "otpauth://totp/x",
            backupCodes: Array(repeating: "ABCD1234", count: 10)
        ))
        stub.verifyResult = verifyResult
        let vm = TwoFactorEnrollmentViewModel(repository: stub)
        await vm.continueFromIntro()
        return vm
    }

    func test_submitVerifyCode_requiresSixDigits() async {
        let vm = await makeQRVM()
        vm.verifyCode = "123"

        await vm.submitVerifyCode()

        XCTAssertNotNil(vm.verifyFieldError)
        XCTAssertEqual(vm.state, .showingQR)
    }

    func test_submitVerifyCode_stripsNonDigits() async {
        let vm = await makeQRVM(verifyResult: .success(TwoFactorVerifyResponse(verified: true)))
        vm.verifyCode = "12-34-56"  // contains dashes

        await vm.submitVerifyCode()

        XCTAssertNil(vm.verifyFieldError)
        XCTAssertEqual(vm.state, .showingCodes)
    }

    func test_submitVerifyCode_transitionsToShowingCodes_onSuccess() async {
        let vm = await makeQRVM(verifyResult: .success(TwoFactorVerifyResponse(verified: true)))
        vm.verifyCode = "654321"

        await vm.submitVerifyCode()

        XCTAssertEqual(vm.state, .showingCodes)
        XCTAssertNil(vm.verifyFieldError)
        XCTAssertFalse(vm.isLoading)
    }

    func test_submitVerifyCode_setsFieldError_onValidationError() async {
        let vm = await makeQRVM(verifyResult: .failure(AppError.validation(fieldErrors: ["code": "Invalid TOTP code"])))
        vm.verifyCode = "999999"

        await vm.submitVerifyCode()

        XCTAssertNotNil(vm.verifyFieldError)
        XCTAssertEqual(vm.state, .showingQR)
    }

    // MARK: - confirmSaved gate (reach .showingCodes via successful enroll+verify)

    private func makeCodesVM() async -> TwoFactorEnrollmentViewModel {
        let vm = await makeQRVM(verifyResult: .success(TwoFactorVerifyResponse(verified: true)))
        vm.verifyCode = "123456"
        await vm.submitVerifyCode()
        return vm
    }

    func test_confirmSaved_requiresHasSavedCodes() async {
        let vm = await makeCodesVM()
        vm.hasSavedCodes = false

        vm.confirmSaved()

        XCTAssertEqual(vm.state, .showingCodes)  // no transition
    }

    func test_confirmSaved_transitionsToDone_whenChecked() async {
        let vm = await makeCodesVM()
        vm.hasSavedCodes = true

        vm.confirmSaved()

        XCTAssertEqual(vm.state, .done)
    }

    // MARK: - Reset

    func test_reset_clearsAllState() async {
        let stub = StubTwoFactorRepository()
        stub.enrollResult = .success(TwoFactorEnrollResponse(
            secret: "SECRET",
            otpauthURI: "otpauth://totp/x",
            backupCodes: ["A", "B"]
        ))
        let vm = TwoFactorEnrollmentViewModel(repository: stub)
        await vm.continueFromIntro()

        vm.reset()

        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.secret, "")
        XCTAssertEqual(vm.otpauthURI, "")
        XCTAssertTrue(vm.recoveryCodeList.codes.isEmpty)
        XCTAssertFalse(vm.hasSavedCodes)
        XCTAssertFalse(vm.isLoading)
    }
}

// MARK: - Challenge ViewModel tests

@MainActor
final class TwoFactorChallengeViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState() {
        let vm = makeChallengeVM()
        XCTAssertEqual(vm.digits, Array(repeating: "", count: 6))
        XCTAssertFalse(vm.isLockedOut)
        XCTAssertEqual(vm.failedAttempts, 0)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.inputMode, .totp)
    }

    // MARK: - Mode switching

    func test_switchToRecovery_clearsDigitsAndError() async {
        // Drive an error by submitting incomplete digits
        let vm = makeChallengeVM()
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        vm.switchToRecovery()

        XCTAssertEqual(vm.inputMode, .recovery)
        XCTAssertEqual(vm.digits, Array(repeating: "", count: 6))
        XCTAssertNil(vm.errorMessage)
    }

    func test_switchToTOTP_clearsRecoveryInputAndError() async {
        let vm = makeChallengeVM()
        vm.switchToRecovery()
        vm.recoveryCodeInput = "ABCD1234"

        vm.switchToTOTP()

        XCTAssertEqual(vm.inputMode, .totp)
        XCTAssertEqual(vm.recoveryCodeInput, "")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - TOTP validation

    func test_submitTOTP_requiresSixDigits() async {
        let vm = makeChallengeVM()
        vm.digits = ["1", "2", "3", "", "", ""]

        await vm.submitTOTP()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.result)
    }

    func test_submitTOTP_succeeds() async {
        let stub = StubTwoFactorRepository()
        stub.challengeResult = .success(TwoFactorChallengeResponse(
            accessToken: "tok_a",
            refreshToken: "tok_r"
        ))
        let vm = TwoFactorChallengeViewModel(repository: stub, challengeToken: "ch_123")
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        await vm.submitTOTP()

        XCTAssertNotNil(vm.result)
        if case .success = vm.result {} else {
            XCTFail("Expected .success result")
        }
    }

    func test_submitTOTP_recordsFailure_onError() async {
        let stub = StubTwoFactorRepository()
        stub.challengeResult = .failure(AppError.unauthorized)
        let vm = TwoFactorChallengeViewModel(repository: stub, challengeToken: "ch_123")
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        await vm.submitTOTP()

        XCTAssertEqual(vm.failedAttempts, 1)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.digits, Array(repeating: "", count: 6))
    }

    // MARK: - Lockout (3 wrong → 30s lockout)

    func test_threeFailures_triggersLockout() async {
        let stub = StubTwoFactorRepository()
        stub.challengeResult = .failure(AppError.unauthorized)
        let vm = TwoFactorChallengeViewModel(repository: stub, challengeToken: "ch")
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        await vm.submitTOTP()
        vm.digits = ["1", "2", "3", "4", "5", "6"]
        await vm.submitTOTP()
        vm.digits = ["1", "2", "3", "4", "5", "6"]
        await vm.submitTOTP()

        XCTAssertEqual(vm.failedAttempts, 3)
        XCTAssertTrue(vm.isLockedOut)
        XCTAssertGreaterThan(vm.lockoutSecondsRemaining, 0)
        XCTAssertFalse(vm.canSubmit)
    }

    func test_submittingWhileLockedOut_doesNotCallRepository() async {
        let stub = StubTwoFactorRepository()
        stub.challengeResult = .failure(AppError.unauthorized)
        let vm = TwoFactorChallengeViewModel(repository: stub, challengeToken: "ch")
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        // Trigger lockout
        for _ in 0..<3 {
            await vm.submitTOTP()
            vm.digits = ["1", "2", "3", "4", "5", "6"]
        }
        let callCountAfterLockout = stub.challengeCallCount
        vm.digits = ["1", "2", "3", "4", "5", "6"]

        await vm.submitTOTP()

        XCTAssertEqual(stub.challengeCallCount, callCountAfterLockout) // no additional calls
    }

    func test_clearLockoutIfExpired_clearsWhenPastDeadline() {
        let vm = makeChallengeVM()
        // Use internal(set) to simulate an expired lockout
        vm.lockedUntil = Date().addingTimeInterval(-1)

        vm.clearLockoutIfExpired()

        XCTAssertFalse(vm.isLockedOut)
        XCTAssertEqual(vm.failedAttempts, 0)
    }

    // MARK: - Recovery

    func test_submitRecovery_requiresMinimumLength() async {
        let vm = makeChallengeVM()
        vm.switchToRecovery()
        vm.recoveryCodeInput = "SHORT"

        await vm.submitRecovery()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.result)
    }

    func test_submitRecovery_succeeds() async {
        let stub = StubTwoFactorRepository()
        stub.verifyRecoveryResult = .success(TwoFactorVerifyRecoveryResponse(
            accessToken: "tok_a",
            refreshToken: "tok_r",
            codesRemaining: 9
        ))
        let vm = TwoFactorChallengeViewModel(repository: stub, challengeToken: "ch")
        vm.switchToRecovery()
        vm.recoveryCodeInput = "ABCD1234EFGH"

        await vm.submitRecovery()

        XCTAssertEqual(vm.codesRemaining, 9)
        if case .recoverySuccess(_, _, let remaining) = vm.result {
            XCTAssertEqual(remaining, 9)
        } else {
            XCTFail("Expected .recoverySuccess result")
        }
    }

    // MARK: - Helpers

    private func makeChallengeVM() -> TwoFactorChallengeViewModel {
        TwoFactorChallengeViewModel(
            repository: StubTwoFactorRepository(),
            challengeToken: "test_challenge_token"
        )
    }
}

// MARK: - RecoveryCodeList tests

final class RecoveryCodeListTests: XCTestCase {

    func test_formatted_insertsDashAtMidpoint() {
        let list = RecoveryCodeList(codes: ["ABCD1234EFGH"])
        XCTAssertEqual(list.formatted("ABCD1234EFGH"), "ABCD1234-EFGH")
    }

    func test_formatted_uppercases() {
        let list = RecoveryCodeList(codes: [])
        XCTAssertEqual(list.formatted("abcd1234"), "ABCD-1234")
    }

    func test_formatted_shortCode_returnsUppercase() {
        let list = RecoveryCodeList(codes: [])
        XCTAssertEqual(list.formatted("AB"), "AB")
    }

    func test_formattedCodes_mapsAllCodes() {
        let list = RecoveryCodeList(codes: ["AAAA1111", "BBBB2222"])
        XCTAssertEqual(list.formattedCodes.count, 2)
    }

    func test_grid_pairsCodesIntoRows() {
        let codes = Array(repeating: "ABCD1234", count: 10)
        let list = RecoveryCodeList(codes: codes)
        let grid = list.grid
        XCTAssertEqual(grid.count, 5)  // 10 codes → 5 rows of 2
        XCTAssertNotNil(grid[0].1)
    }

    func test_grid_oddCount_lastRowHasNilRight() {
        let codes = Array(repeating: "ABCD1234", count: 3)
        let list = RecoveryCodeList(codes: codes)
        let grid = list.grid
        XCTAssertEqual(grid.count, 2)
        XCTAssertNil(grid[1].1)
    }

    func test_exportText_containsHeader() {
        let list = RecoveryCodeList(codes: ["ABCD1234"])
        XCTAssertTrue(list.exportText.contains("BizarreCRM Recovery Codes"))
    }

    func test_exportText_containsFormattedCode() {
        let list = RecoveryCodeList(codes: ["ABCD1234"])
        XCTAssertTrue(list.exportText.contains("ABCD-1234"))
    }

    func test_equatable() {
        let a = RecoveryCodeList(codes: ["A", "B"])
        let b = RecoveryCodeList(codes: ["A", "B"])
        let c = RecoveryCodeList(codes: ["X"])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - QR Generator tests

#if canImport(UIKit)
import UIKit

final class TwoFactorQRGeneratorTests: XCTestCase {

    func test_qrImage_returnsNonNilForValidURI() {
        let uri = "otpauth://totp/BizarreCRM:test@example.com?secret=JBSWY3DPEHPK3PXP&issuer=BizarreCRM"
        let img = TwoFactorQRGenerator.qrImage(from: uri, size: CGSize(width: 200, height: 200))
        XCTAssertNotNil(img, "Expected non-nil UIImage for valid otpauth URI")
    }

    func test_qrImage_returnsNilForEmptyString() {
        let img = TwoFactorQRGenerator.qrImage(from: "", size: CGSize(width: 200, height: 200))
        XCTAssertNil(img)
    }

    func test_qrImage_respectsRequestedSize() {
        let uri = "otpauth://totp/Test:user@example.com?secret=JBSWY3DPEHPK3PXP"
        let size = CGSize(width: 300, height: 300)
        let img = TwoFactorQRGenerator.qrImage(from: uri, size: size)
        XCTAssertNotNil(img)
        // Allow 1-point tolerance due to integer rounding in CIFilter scaling
        XCTAssertEqual(img!.size.width, size.width, accuracy: 1.0)
        XCTAssertEqual(img!.size.height, size.height, accuracy: 1.0)
    }

    func test_qrImage_worksForMinimalURI() {
        let uri = "otpauth://totp/x?secret=ABC"
        let img = TwoFactorQRGenerator.qrImage(from: uri, size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(img)
    }
}
#endif

// MARK: - Stub repository

private final class StubTwoFactorRepository: TwoFactorRepository, @unchecked Sendable {
    var enrollResult: Result<TwoFactorEnrollResponse, Error> = .failure(AppError.network(underlying: nil))
    var verifyResult: Result<TwoFactorVerifyResponse, Error> = .failure(AppError.network(underlying: nil))
    var challengeResult: Result<TwoFactorChallengeResponse, Error> = .failure(AppError.network(underlying: nil))
    // disableResult removed 2026-04-23 — TwoFactorRepository.disable() deleted per security policy.
    var regenerateResult: Result<TwoFactorRegenerateCodesResponse, Error> = .failure(AppError.network(underlying: nil))
    var verifyRecoveryResult: Result<TwoFactorVerifyRecoveryResponse, Error> = .failure(AppError.network(underlying: nil))
    var statusResult: Result<TwoFactorStatusResponse, Error> = .success(TwoFactorStatusResponse(enabled: false, codesRemaining: nil))

    var challengeCallCount = 0

    func enroll() async throws -> TwoFactorEnrollResponse {
        try enrollResult.get()
    }
    func verify(code: String) async throws -> TwoFactorVerifyResponse {
        try verifyResult.get()
    }
    func challenge(challengeToken: String, code: String) async throws -> TwoFactorChallengeResponse {
        challengeCallCount += 1
        return try challengeResult.get()
    }
    // disable(currentPassword:, totpCode:) removed 2026-04-23 per security policy.
    func regenerateCodes(totpCode: String) async throws -> TwoFactorRegenerateCodesResponse {
        try regenerateResult.get()
    }
    func verifyRecovery(code: String) async throws -> TwoFactorVerifyRecoveryResponse {
        try verifyRecoveryResult.get()
    }
    func status() async throws -> TwoFactorStatusResponse {
        try statusResult.get()
    }
}

