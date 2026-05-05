import XCTest
@testable import Estimates
import Networking
import Sync

// MARK: - EstimateListPerfTests

/// Phase-3 gate: every list must scroll 1000 rows at 60 fps+.
/// Measures the data-layer read path of `EstimateCachedRepositoryImpl`.
final class EstimateListPerfTests: XCTestCase {

    // MARK: - 1000-row hot-read benchmark

    func testCachedListHotRead1000Rows() async throws {
        let api = SpyEstimateAPIClient1000()
        let repo = EstimateCachedRepositoryImpl(api: api)

        // Populate cache.
        _ = try await repo.forceRefresh(keyword: nil)

        let start = Date()
        for _ in 0..<100 {
            let result = try await repo.cachedList(keyword: nil, maxAgeSeconds: 60)
            XCTAssertEqual(result.value.count, 1000)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "100 hot reads of 1000 rows took \(elapsed)s — exceeds 1s budget")
    }

    // MARK: - ViewModel fetch benchmark

    func testViewModelFetch1000Items() async throws {
        let api = SpyEstimateAPIClient1000()
        let repo = EstimateCachedRepositoryImpl(api: api)
        // Pre-warm.
        _ = try await repo.forceRefresh(keyword: nil)

        let vm = await EstimateListViewModel(repo: repo)

        let start = Date()
        for _ in 0..<10 {
            await vm.load()
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "10 VM loads took \(elapsed)s — exceeds 2s budget")

        let count = await vm.items.count
        XCTAssertEqual(count, 1000)
    }
}

// MARK: - SpyEstimateAPIClient1000

private actor SpyEstimateAPIClient1000: APIClient {

    private let response: EstimatesListResponse = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let estimatesJsonArray = (0..<1000).map { i in
            "{\"id\":\(i+1),\"order_id\":\"EST-\(i+1)\",\"customer_id\":1,\"customer_first_name\":\"Customer\",\"customer_last_name\":\"\(i)\",\"status\":\"draft\",\"total\":\(Double(i)*10.5),\"valid_until\":\"2026-12-31\",\"is_expiring\":false}"
        }.joined(separator: ",")
        let responseJson = "{\"estimates\":[\(estimatesJsonArray)]}".data(using: .utf8)!
        return try! decoder.decode(EstimatesListResponse.self, from: responseJson)
    }()

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/estimates" else { throw APITransportError.noBaseURL }
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
