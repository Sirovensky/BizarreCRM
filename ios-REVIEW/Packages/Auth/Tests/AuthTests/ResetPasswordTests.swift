import XCTest
@testable import Auth

// MARK: - ResetPasswordViewModel tests

final class ResetPasswordViewModelTests: XCTestCase {

    // MARK: - canSubmit logic

    func test_canSubmit_falseWhenEmpty() {
        let vm = ResetPasswordViewModel(token: "tok", api: MockAPIClientStub())
        XCTAssertFalse(vm.canSubmit)
    }

    func test_canSubmit_falseWhenPasswordTooShort() {
        let vm = ResetPasswordViewModel(token: "tok", api: MockAPIClientStub())
        vm.newPassword = "abc"
        vm.confirmPassword = "abc"
        XCTAssertFalse(vm.canSubmit, "Password < 8 chars should not allow submit")
    }

    func test_canSubmit_falseWhenMismatch() {
        let vm = ResetPasswordViewModel(token: "tok", api: MockAPIClientStub())
        vm.newPassword = "strongPass1!"
        vm.confirmPassword = "differentPass1!"
        XCTAssertFalse(vm.canSubmit, "Mismatched passwords should not allow submit")
    }

    func test_canSubmit_trueWhenValid() {
        let vm = ResetPasswordViewModel(token: "tok", api: MockAPIClientStub())
        vm.newPassword = "strongPass1!"
        vm.confirmPassword = "strongPass1!"
        XCTAssertTrue(vm.canSubmit)
    }

    func test_canSubmit_falseWhileSubmitting() {
        let vm = ResetPasswordViewModel(token: "tok", api: MockAPIClientStub())
        vm.newPassword = "strongPass1!"
        vm.confirmPassword = "strongPass1!"
        vm.isSubmitting = true
        XCTAssertFalse(vm.canSubmit, "Should not allow submit while already submitting")
    }
}

// MARK: - AuthLogPrivacy tests

final class AuthLogPrivacyTests: XCTestCase {

    func test_bannedFields_containsExpectedKeys() {
        let banned = AuthLogPrivacy.bannedFields
        XCTAssertTrue(banned.contains("password"))
        XCTAssertTrue(banned.contains("accessToken"))
        XCTAssertTrue(banned.contains("refreshToken"))
        XCTAssertTrue(banned.contains("pin"))
        XCTAssertTrue(banned.contains("backupCode"))
    }

    func test_presence_nonEmpty_returnsSet() {
        XCTAssertEqual(AuthLogPrivacy.presence("someValue"), "[set]")
    }

    func test_presence_empty_returnsEmpty() {
        XCTAssertEqual(AuthLogPrivacy.presence(""), "[empty]")
    }

    func test_presence_nil_returnsEmpty() {
        XCTAssertEqual(AuthLogPrivacy.presence(nil as String?), "[empty]")
    }

    func test_redacted_returnsPlaceholder() {
        let result = AuthLogPrivacy.redacted("accessToken")
        XCTAssertTrue(result.contains("REDACTED"))
        XCTAssertTrue(result.contains("accessToken"))
    }
}

// MARK: - Minimal mock (macOS / iOS test target, no UI)

// A trivial stand-in that throws `.noBaseURL` on every call.
// Not a full APIClient mock — we only test ViewModel logic here.
import Networking

private final class MockAPIClientStub: APIClient {
    var baseURL: URL? { nil }
    func setBaseURL(_ url: URL?) async {}
    func get<T: Decodable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIEnvelope<T> {
        throw APITransportError.noBaseURL
    }
}
