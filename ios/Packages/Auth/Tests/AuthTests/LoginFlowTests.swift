import XCTest
@testable import Auth
import Networking

@MainActor
final class LoginFlowTests: XCTestCase {
    func test_initialStep_isServer() {
        // Login flow opens on SERVER selection — per §2.1 the user picks a
        // tenant (or flips to self-hosted) before anything else. A silent
        // change to `.credentials` would re-introduce the legacy behaviour.
        let flow = LoginFlow(api: StubAPIClient())
        XCTAssertEqual(flow.step, .server)
        XCTAssertFalse(flow.isSubmitting)
        XCTAssertFalse(flow.useSelfHosted)
    }

    func test_beginRegister_movesToRegisterStep() {
        let flow = LoginFlow(api: StubAPIClient())
        flow.beginRegister()
        XCTAssertEqual(flow.step, .register)
    }

    func test_beginForgotPassword_clearsPriorMessageAndMovesStep() {
        let flow = LoginFlow(api: StubAPIClient())
        flow.errorMessage = "stale"
        flow.forgotMessage = "stale"
        flow.beginForgotPassword()
        XCTAssertNil(flow.errorMessage)
        XCTAssertNil(flow.forgotMessage)
        XCTAssertEqual(flow.step, .forgotPassword)
    }
}

/// Minimum-surface stub — conforms to the current `APIClient` protocol but
/// throws on every network call. LoginFlowTests only exercise state
/// transitions that don't reach the network.
private actor StubAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
