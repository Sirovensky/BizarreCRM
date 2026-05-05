import XCTest
@testable import Auth
import Networking

// MARK: - §2.9 Change password view model tests

@MainActor
final class ChangePasswordViewModelTests: XCTestCase {

    // MARK: - Validation

    func testCanSubmitFalseWhenCurrentPasswordEmpty() {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub())
        vm.newPassword = "Correct1!"
        vm.confirmPassword = "Correct1!"
        XCTAssertFalse(vm.canSubmit)
    }

    func testCanSubmitFalseWhenPasswordsMismatch() {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub())
        vm.currentPassword = "old"
        vm.newPassword = "NewPass1!"
        vm.confirmPassword = "NewPass2!"
        XCTAssertFalse(vm.canSubmit)
    }

    func testMismatchFalseWhenConfirmEmpty() {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub())
        vm.newPassword = "NewPass1!"
        XCTAssertFalse(vm.mismatch)
    }

    func testMismatchTrueWhenDifferent() {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub())
        vm.newPassword = "NewPass1!"
        vm.confirmPassword = "OtherPass2!"
        XCTAssertTrue(vm.mismatch)
    }

    // MARK: - API interaction

    func testSuccessfulChangeProducesSuccessMessage() async {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub(shouldSucceed: true))
        vm.currentPassword = "OldPass1!"
        vm.newPassword = "NewPass2@"
        vm.confirmPassword = "NewPass2@"
        await vm.submit()
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.successMessage)
    }

    func test401ProducesIncorrectError() async {
        let vm = ChangePasswordViewModel(api: ChangePasswordStub(shouldSucceed: false))
        vm.currentPassword = "wrong"
        vm.newPassword = "NewPass2@"
        vm.confirmPassword = "NewPass2@"
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("incorrect") == true)
        XCTAssertNil(vm.successMessage)
    }
}

// MARK: - Stub

private actor ChangePasswordStub: APIClient {
    let shouldSucceed: Bool
    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func changePassword(currentPassword: String, newPassword: String) async throws {
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
