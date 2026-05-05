import XCTest
@testable import Estimates
import Networking
import Sync

// MARK: - EstimateCachedRepositoryTests

/// Unit tests for `EstimateCachedRepositoryImpl`.
/// Coverage: cache miss, cache hit, staleness, forceRefresh.
final class EstimateCachedRepositoryTests: XCTestCase {

    // MARK: - Cold read is stale

    func testColdReadIsStale() async throws {
        let api = SpyEstimateAPIClient(estimates: [])
        let repo = EstimateCachedRepositoryImpl(api: api)

        let result = try await repo.cachedList(keyword: nil, maxAgeSeconds: 300)

        XCTAssertTrue(result.isStale)
        XCTAssertNil(result.lastSyncedAt)
        XCTAssertTrue(result.value.isEmpty)
    }

    // MARK: - forceRefresh returns remote data

    func testForceRefreshPopulatesCache() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1), sample(id: 2)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(keyword: nil)

        XCTAssertEqual(result.value.count, 2)
        XCTAssertEqual(result.source, .remote)
        XCTAssertFalse(result.isStale)
        XCTAssertNotNil(result.lastSyncedAt)
    }

    // MARK: - Hot read after refresh is not stale

    func testHotReadAfterRefreshIsNotStale() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(keyword: nil)
        let result = try await repo.cachedList(keyword: nil, maxAgeSeconds: 300)

        XCTAssertFalse(result.isStale)
        XCTAssertEqual(result.value.count, 1)
    }

    // MARK: - maxAgeSeconds=0 always stale

    func testMaxAge0AlwaysStale() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(keyword: nil)
        let result = try await repo.cachedList(keyword: nil, maxAgeSeconds: 0)

        XCTAssertTrue(result.isStale)
    }

    // MARK: - lastSyncedAt updated after refresh

    func testLastSyncedAtUpdated() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        let before = await repo.lastSyncedAt
        XCTAssertNil(before)
        _ = try await repo.forceRefresh(keyword: nil)
        let after = await repo.lastSyncedAt
        XCTAssertNotNil(after)
    }

    // MARK: - Different keywords have independent caches

    func testKeywordsHaveIsolatedCaches() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(keyword: nil)

        // Different keyword = cold cache.
        let result = try await repo.cachedList(keyword: "foo", maxAgeSeconds: 300)
        XCTAssertTrue(result.isStale)
    }

    // MARK: - Legacy list() delegates through cached path

    func testLegacyListDelegates() async throws {
        let api = SpyEstimateAPIClient(estimates: [])
        let repo = EstimateCachedRepositoryImpl(api: api)

        let items = try await repo.list(keyword: nil)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - EstimateRepositoryImpl delegates to API

    func testEstimateRepositoryImplDelegatesToAPI() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1), sample(id: 2)])
        let repo = EstimateRepositoryImpl(api: api)

        let items = try await repo.list(keyword: nil)
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - forceRefresh source is remote

    func testForceRefreshSourceIsRemote() async throws {
        let api = SpyEstimateAPIClient(estimates: [sample(id: 1)])
        let repo = EstimateCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(keyword: nil)
        XCTAssertEqual(result.source, .remote)
    }

    // MARK: - Helpers

    private func sample(id: Int64) -> Estimate {
        let json = """
        {"id":\(id),"order_id":"EST-\(id)","customer_id":1,"customer_first_name":"Test","customer_last_name":"Customer","status":"draft","total":100.0,"valid_until":"2026-12-31","is_expiring":false}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Estimate.self, from: json)
    }
}

// MARK: - SpyEstimateAPIClient

/// Intercepts `get("/api/v1/estimates", ...)` to return an `EstimatesListResponse`.
private actor SpyEstimateAPIClient: APIClient {
    let estimates: [Estimate]

    init(estimates: [Estimate]) {
        self.estimates = estimates
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/estimates" else { throw APITransportError.noBaseURL }
        let estimatesJson = estimates.map { est in
            "{\"id\":\(est.id),\"order_id\":\"\(est.orderId ?? "EST-?")\",\"status\":\"\(est.status ?? "draft")\",\"total\":\(est.total ?? 0),\"valid_until\":\"\(est.validUntil ?? "2026-12-31")\"}"
        }.joined(separator: ",")
        let responseJson = "{\"estimates\":[\(estimatesJson)]}".data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(EstimatesListResponse.self, from: responseJson)
        guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
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
