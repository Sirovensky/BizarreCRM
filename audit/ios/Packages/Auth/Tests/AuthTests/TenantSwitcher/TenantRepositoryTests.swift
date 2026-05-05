import XCTest
@testable import Auth
import Networking
import Core

// MARK: - LiveTenantRepositoryTests

final class TenantRepositoryTests: XCTestCase {

    // MARK: loadTenants

    func test_loadTenants_returnsTenantList_onSuccess() async throws {
        let api = StubAPIClientForRepo(mode: .successTenants)
        let repo = LiveTenantRepository(api: api)
        let result = try await repo.loadTenants()
        XCTAssertEqual(result.count, 2)
    }

    func test_loadTenants_throwsAppError_onNetworkFailure() async {
        let api = FailingAPIClient(error: APITransportError.networkUnavailable)
        let repo = LiveTenantRepository(api: api)
        do {
            _ = try await repo.loadTenants()
            XCTFail("Expected error")
        } catch let err as AppError {
            _ = err // Successfully mapped to AppError
        } catch {
            XCTFail("Expected AppError, got \(error)")
        }
    }

    func test_loadTenants_throwsAppError_on401() async {
        let api = FailingAPIClient(error: APITransportError.httpStatus(401, message: "Unauthorized"))
        let repo = LiveTenantRepository(api: api)
        do {
            _ = try await repo.loadTenants()
            XCTFail("Expected error")
        } catch is AppError {
            // good
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: switchTenant

    func test_switchTenant_returnsTokenPair_onSuccess() async throws {
        let api = StubAPIClientForRepo(mode: .successSwitch)
        let repo = LiveTenantRepository(api: api)
        let (access, _) = try await repo.switchTenant(tenantId: "tenant-1")
        XCTAssertEqual(access, "fresh-token-abc")
    }

    func test_switchTenant_throwsAppError_onServerError() async {
        let api = FailingAPIClient(error: APITransportError.httpStatus(403, message: "Forbidden"))
        let repo = LiveTenantRepository(api: api)
        do {
            _ = try await repo.switchTenant(tenantId: "any")
            XCTFail("Expected error")
        } catch is AppError {
            // good
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: revokeTenantSession

    func test_revokeTenantSession_doesNotThrow_onSuccess() async {
        let api = StubAPIClientForRepo(mode: .successRevoke)
        let repo = LiveTenantRepository(api: api)
        await assertNoThrow { try await repo.revokeTenantSession() }
    }

    func test_revokeTenantSession_doesNotThrow_onFailure() async {
        // revoke is non-fatal — errors are swallowed
        let api = FailingAPIClient(error: APITransportError.networkUnavailable)
        let repo = LiveTenantRepository(api: api)
        await assertNoThrow { try await repo.revokeTenantSession() }
    }
}

// MARK: - Helper

private func assertNoThrow(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
    } catch {
        XCTFail("Unexpected throw: \(error)", file: file, line: line)
    }
}

// MARK: - Stub JSON payloads (avoids encoding internal types)

private let tenantsJSON = """
{
  "tenants": [
    { "id": "t1", "name": "Acme", "slug": "acme", "role": "admin" },
    { "id": "t2", "name": "Globex", "slug": "globex", "role": "tech" }
  ]
}
""".data(using: .utf8)!

private let switchJSON = """
{ "accessToken": "fresh-token-abc", "refreshToken": "fresh-refresh-abc" }
""".data(using: .utf8)!

private let revokeJSON = """
{ "message": "ok" }
""".data(using: .utf8)!

// MARK: - API stubs

private enum StubMode { case successTenants, successSwitch, successRevoke }

private actor StubAPIClientForRepo: APIClient {
    private let mode: StubMode
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(mode: StubMode) { self.mode = mode }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard mode == .successTenants else { throw APITransportError.notImplemented }
        return try decoder.decode(T.self, from: tenantsJSON)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        let data: Data
        switch mode {
        case .successSwitch:  data = switchJSON
        case .successRevoke:  data = revokeJSON
        default: throw APITransportError.notImplemented
        }
        return try decoder.decode(T.self, from: data)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

/// Always fails with a given error.
private actor FailingAPIClient: APIClient {
    private let error: any Error
    init(error: any Error) { self.error = error }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw error }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw error }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw error }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw error }
    func delete(_ path: String) async throws { throw error }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw error }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
