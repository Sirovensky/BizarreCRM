import XCTest
@testable import Employees
@testable import Networking

// MARK: - Mock

actor MockEmployeeAPIClient: APIClient {
    enum Outcome {
        case success([Employee])
        case failure(Error)
    }

    var outcome: Outcome = .success([])
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/employees" else { throw APITransportError.noBaseURL }
        callCount += 1
        switch outcome {
        case .success(let rows):
            guard let cast = rows as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure(let err):
            throw err
        }
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}

    func set(_ o: Outcome) { outcome = o }
}

// MARK: - Fixture

extension Employee {
    static func fixture(id: Int64 = 1, firstName: String = "Alice", lastName: String = "Smith") -> Employee {
        let dict: [String: Any] = ["id": id, "first_name": firstName, "last_name": lastName]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Employee.self, from: data)
    }
}

// MARK: - Tests

final class EmployeeCachedRepositoryTests: XCTestCase {

    func test_cacheHit_noSecondNetworkCall() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.success([.fixture()]))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listEmployees()
        _ = try await repo.listEmployees()

        let count = await api.callCount
        XCTAssertEqual(count, 1)
    }

    func test_expiredCache_refetches() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.success([.fixture()]))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: -1) // always stale

        _ = try await repo.listEmployees()
        _ = try await repo.listEmployees()

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_forceRefresh_bypassesCache() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.success([.fixture()]))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listEmployees()
        _ = try await repo.forceRefresh()

        let count = await api.callCount
        XCTAssertEqual(count, 2)
    }

    func test_lastSyncedAt_nilBeforeFetch() async throws {
        let api = MockEmployeeAPIClient()
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_setAfterFetch() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.success([.fixture()]))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.listEmployees()
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ts), before)
    }

    func test_errorPropagates() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.failure(APITransportError.noBaseURL))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        do {
            _ = try await repo.listEmployees()
            XCTFail("Expected error")
        } catch { /* correct */ }
    }

    func test_returnsCorrectRows() async throws {
        let api = MockEmployeeAPIClient()
        await api.set(.success([.fixture(id: 99, firstName: "Bob", lastName: "Jones")]))
        let repo = EmployeeCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let rows = try await repo.listEmployees()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 99)
        XCTAssertEqual(rows.first?.displayName, "Bob Jones")
    }
}
