import XCTest
@testable import Auth
import Networking

// MARK: - §2.2 LoginFlow validation + rate-limit + trust-device tests

@MainActor
final class LoginFlowValidationTests: XCTestCase {

    // MARK: - §2.2 Form validation guard

    func test_submitCredentials_emptyUsername_setsError() async {
        let api = RejectingAPIClient()
        let flow = LoginFlow(api: api)
        flow.username = ""
        flow.password = "somepassword"
        // Force step to credentials so the guard runs
        flow.step = .credentials

        await flow.submitCredentials()

        XCTAssertNotNil(flow.errorMessage)
        XCTAssertFalse(flow.isSubmitting)
    }

    func test_submitCredentials_emptyPassword_setsError() async {
        let api = RejectingAPIClient()
        let flow = LoginFlow(api: api)
        flow.username = "testuser"
        flow.password = ""
        flow.step = .credentials

        await flow.submitCredentials()

        XCTAssertNotNil(flow.errorMessage)
    }

    // MARK: - §2.2 Trust-device flag is initially false

    func test_trustDevice_defaultIsFalse() {
        let flow = LoginFlow(api: RejectingAPIClient())
        XCTAssertFalse(flow.trustDevice)
    }

    // MARK: - §2.1 isProbing starts false

    func test_isProbing_startsAsFalse() {
        let flow = LoginFlow(api: RejectingAPIClient())
        XCTAssertFalse(flow.isProbing)
    }

    // MARK: - §2.11 sessionRevokedMessage

    func test_handleSessionRevoked_withNilMessage_usesDefault() {
        let flow = LoginFlow(api: RejectingAPIClient())
        flow.handleSessionRevoked(message: nil)
        XCTAssertNotNil(flow.sessionRevokedMessage)
    }

    func test_handleSessionRevoked_withMessage_usesProvidedMessage() {
        let flow = LoginFlow(api: RejectingAPIClient())
        let msg = "Session revoked from admin panel"
        flow.handleSessionRevoked(message: msg)
        XCTAssertEqual(flow.sessionRevokedMessage, msg)
    }

    // MARK: - §2.11 currentUser starts nil

    func test_currentUser_startsNil() {
        let flow = LoginFlow(api: RejectingAPIClient())
        XCTAssertNil(flow.currentUser)
    }

    // MARK: - §2.12 isAccountLocked starts false

    func test_isAccountLocked_defaultIsFalse() {
        let flow = LoginFlow(api: RejectingAPIClient())
        XCTAssertFalse(flow.isAccountLocked)
    }
}

// MARK: - Stub that throws on any network call

private actor RejectingAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.networkUnavailable
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.networkUnavailable
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
