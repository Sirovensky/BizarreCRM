import XCTest
@testable import Auth
@testable import Networking

// MARK: - SetupStatusProbeTests
// §2.1 — Verifies probe routing: needsSetup vs normal login vs 404 fallback.

final class SetupStatusProbeTests: XCTestCase {

    func test_resolved_whenServerReturnsNeedsSetup() async throws {
        let api = MockSetupStatusAPI(status: AuthSetupStatus(needsSetup: true, isMultiTenant: false))
        let probe = SetupStatusProbe(api: api)
        let result = await probe.run()
        guard case .resolved(let status) = result else {
            XCTFail("Expected .resolved"); return
        }
        XCTAssertTrue(status.needsSetup)
    }

    func test_resolved_normalLogin() async throws {
        let api = MockSetupStatusAPI(status: AuthSetupStatus(needsSetup: false, isMultiTenant: nil))
        let probe = SetupStatusProbe(api: api)
        let result = await probe.run()
        guard case .resolved(let status) = result else {
            XCTFail("Expected .resolved"); return
        }
        XCTAssertFalse(status.needsSetup)
    }

    func test_failure_onNetworkError() async {
        let api = MockSetupStatusAPI(shouldFail: true)
        let probe = SetupStatusProbe(api: api)
        let result = await probe.run()
        guard case .failure = result else {
            XCTFail("Expected .failure"); return
        }
    }
}

// MARK: - Mock

private final class MockSetupStatusAPI: APIClient, @unchecked Sendable {
    private let result: Result<AuthSetupStatus, Error>

    init(status: AuthSetupStatus) {
        result = .success(status)
    }

    init(shouldFail: Bool) {
        result = .failure(URLError(.notConnectedToInternet))
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        switch result {
        case .success(let s):
            guard let t = s as? T else { throw URLError(.unsupportedURL) }
            return t
        case .failure(let e):
            throw e
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.unsupportedURL) }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.unsupportedURL) }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw URLError(.unsupportedURL) }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw URLError(.unsupportedURL) }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
