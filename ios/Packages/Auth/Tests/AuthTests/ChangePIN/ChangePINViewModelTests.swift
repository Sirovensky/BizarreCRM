import XCTest
@testable import Auth
import Networking

// MARK: - §2.5 Change PIN view model tests

@MainActor
final class ChangePINViewModelTests: XCTestCase {

    // MARK: - Validation

    func testCanSubmitFalseWhenCurrentPINEmpty() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.newPIN = "1234"
        vm.confirmPIN = "1234"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitFalseWhenPINsMismatch() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.currentPIN = "1234"
        vm.newPIN = "5678"
        vm.confirmPIN = "5679"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitFalseWhenNewPINTooShort() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.currentPIN = "1234"
        vm.newPIN = "123"
        vm.confirmPIN = "123"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitTrueWhenValid() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.currentPIN = "1234"
        vm.newPIN = "5678"
        vm.confirmPIN = "5678"
        XCTAssertTrue(vm.canSubmit)
    }

    func testMismatchTrueWhenConfirmDiffers() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.newPIN = "1234"
        vm.confirmPIN = "5678"
        XCTAssertTrue(vm.mismatch)
    }

    func testMismatchFalseWhenConfirmEmpty() {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.newPIN = "1234"
        vm.confirmPIN = ""
        XCTAssertFalse(vm.mismatch)
    }

    // MARK: - Common PIN blocklist

    func testCommonPINsAreBlocked() async {
        let vm = ChangePINViewModel(api: MockAPIClient())
        vm.currentPIN = "9999"
        vm.newPIN = "1234"
        vm.confirmPIN = "1234"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("common") == true)
    }

    // MARK: - API interaction

    func testSuccessfulChangeClearsFields() async {
        let mock = MockAPIClient()
        let vm = ChangePINViewModel(api: mock)
        vm.currentPIN = "4321"
        vm.newPIN = "9876"
        vm.confirmPIN = "9876"
        await vm.submit()
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.successMessage)
        XCTAssertTrue(vm.currentPIN.isEmpty)
        XCTAssertTrue(vm.newPIN.isEmpty)
        XCTAssertTrue(vm.confirmPIN.isEmpty)
    }
}

// MARK: - Minimal MockAPIClient for this test file

private final class MockAPIClient: APIClient, @unchecked Sendable {
    // All calls succeed by default. Override in specific tests as needed.
    func changePIN(currentPin: String, newPin: String) async throws { }
    func changePassword(currentPassword: String, newPassword: String) async throws { }
}
