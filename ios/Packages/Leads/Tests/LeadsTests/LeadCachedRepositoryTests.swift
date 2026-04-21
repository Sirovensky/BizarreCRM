import XCTest
@testable import Leads
@testable import Networking

// MARK: - Mock

/// Hand-rolled stub that only wires `listLeads`. Other protocol requirements
/// throw `.noBaseURL` so accidental extra calls surface immediately.
actor MockLeadAPIClient: APIClient {
    enum Outcome {
        case success([Lead])
        case failure(Error)
    }

    var listLeadsOutcome: Outcome = .success([])
    private(set) var callCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/leads" else { throw APITransportError.noBaseURL }
        callCount += 1
        switch listLeadsOutcome {
        case .success(let rows):
            let response = LeadsListResponse(leads: rows)
            guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
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

    func setOutcome(_ outcome: Outcome) { listLeadsOutcome = outcome }
}

// MARK: - Fixtures

extension Lead {
    static func fixture(id: Int64 = 1, firstName: String = "Jane", lastName: String = "Doe") -> Lead {
        let dict: [String: Any] = ["id": id, "first_name": firstName, "last_name": lastName]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Lead.self, from: data)
    }
}

// MARK: - Tests

final class LeadCachedRepositoryTests: XCTestCase {

    // MARK: - Cache hit

    func test_secondCall_doesNotHitNetwork() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.success([.fixture()]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listLeads(keyword: nil)
        _ = try await repo.listLeads(keyword: nil)

        let count = await api.callCount
        XCTAssertEqual(count, 1, "Second call should hit the in-memory cache, not the network")
    }

    // MARK: - Staleness

    func test_expiredCache_hitsNetwork() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.success([.fixture()]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: -1) // always stale

        _ = try await repo.listLeads(keyword: nil)
        _ = try await repo.listLeads(keyword: nil) // should refetch

        let count = await api.callCount
        XCTAssertEqual(count, 2, "Expired cache should trigger a network call")
    }

    // MARK: - Per-keyword isolation

    func test_differentKeywords_separateCacheEntries() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.success([.fixture()]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listLeads(keyword: nil)
        _ = try await repo.listLeads(keyword: "alice") // different key — fresh fetch

        let count = await api.callCount
        XCTAssertEqual(count, 2, "Different keywords must use separate cache entries")
    }

    // MARK: - forceRefresh bypasses cache

    func test_forceRefresh_bypassesCache() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.success([.fixture()]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        _ = try await repo.listLeads(keyword: nil)
        _ = try await repo.forceRefresh(keyword: nil) // must hit network even if fresh

        let count = await api.callCount
        XCTAssertEqual(count, 2, "forceRefresh must bypass the cache and hit the network")
    }

    // MARK: - lastSyncedAt populated after fetch

    func test_lastSyncedAt_nilBeforeFirstFetch() async throws {
        let api = MockLeadAPIClient()
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let timestamp = await repo.lastSyncedAt
        XCTAssertNil(timestamp, "lastSyncedAt must be nil before the first fetch")
    }

    func test_lastSyncedAt_setAfterFetch() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.success([.fixture()]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.listLeads(keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(ts), before)
    }

    // MARK: - Error propagation

    func test_networkError_propagates() async throws {
        let api = MockLeadAPIClient()
        await api.setOutcome(.failure(APITransportError.noBaseURL))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        do {
            _ = try await repo.listLeads(keyword: nil)
            XCTFail("Expected error to propagate")
        } catch {
            // Correct — error surfaces to caller.
        }
    }

    // MARK: - Returns correct rows

    func test_returns_cachedRows() async throws {
        let api = MockLeadAPIClient()
        let lead = Lead.fixture(id: 42, firstName: "Bob", lastName: "Smith")
        await api.setOutcome(.success([lead]))
        let repo = LeadCachedRepositoryImpl(api: api, maxAgeSeconds: 300)

        let rows = try await repo.listLeads(keyword: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)
    }
}
