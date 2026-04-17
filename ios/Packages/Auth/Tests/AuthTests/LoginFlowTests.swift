import XCTest
@testable import Auth
import Networking

@MainActor
final class LoginFlowTests: XCTestCase {
    func test_initialStep_isCredentials() {
        let flow = LoginFlow(api: StubAPIClient())
        XCTAssertEqual(flow.step, .credentials)
        XCTAssertFalse(flow.isSubmitting)
    }
}

private actor StubAPIClient: APIClient {
    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw NSError(domain: "stub", code: -1)
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw NSError(domain: "stub", code: -1)
    }
    func delete(_ path: String) async throws {}
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL) async {}
}
