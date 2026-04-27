import XCTest
@testable import Auth
import Networking

// MARK: - §2.5 Change PIN view model tests

@MainActor
final class ChangePINViewModelTests: XCTestCase {

    // MARK: - Validation

    func testCanSubmitFalseWhenCurrentPINEmpty() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.newPIN = "1234"
        vm.confirmPIN = "1234"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitFalseWhenPINsMismatch() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.currentPIN = "1234"
        vm.newPIN = "5678"
        vm.confirmPIN = "5679"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitFalseWhenNewPINTooShort() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.currentPIN = "1234"
        vm.newPIN = "123"
        vm.confirmPIN = "123"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitTrueWhenValid() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.currentPIN = "1234"
        vm.newPIN = "5678"
        vm.confirmPIN = "5678"
        XCTAssertTrue(vm.canSubmit)
    }

    func testMismatchTrueWhenConfirmDiffers() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.newPIN = "1234"
        vm.confirmPIN = "5678"
        XCTAssertTrue(vm.mismatch)
    }

    func testMismatchFalseWhenConfirmEmpty() {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.newPIN = "1234"
        vm.confirmPIN = ""
        XCTAssertFalse(vm.mismatch)
    }

    // MARK: - Common PIN blocklist

    func testCommonPINsAreBlocked() async {
        let vm = ChangePINViewModel(api: ChangePINStub())
        vm.currentPIN = "9999"
        vm.newPIN = "1234"
        vm.confirmPIN = "1234"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("common") == true)
    }

    // MARK: - API interaction

    func testSuccessfulChangeClearsFields() async {
        let vm = ChangePINViewModel(api: ChangePINStub(shouldSucceed: true))
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

    func test401SetsCurrentPINIncorrectError() async {
        let vm = ChangePINViewModel(api: ChangePINStub(shouldSucceed: false))
        vm.currentPIN = "4321"
        vm.newPIN = "9876"
        vm.confirmPIN = "9876"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("incorrect") == true)
    }
}

// MARK: - Stub

/// Full `APIClient` stub that succeeds or fails `changePIN` on demand.
private actor ChangePINStub: APIClient {
    let shouldSucceed: Bool
    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func changePIN(currentPin: String, newPin: String) async throws {
        if !shouldSucceed { throw APITransportError.httpStatus(401, "Unauthorized") }
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
