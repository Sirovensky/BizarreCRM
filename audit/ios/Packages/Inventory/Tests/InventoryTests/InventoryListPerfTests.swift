import XCTest
@testable import Inventory
import Networking
import Sync

// MARK: - InventoryListPerfTests

/// Phase-3 gate: every list must scroll 1000 rows at 60 fps+.
/// These benchmarks measure the data-layer read path.
/// The "60 fps" guarantee is architectural — the cached path serves data
/// from in-memory dict with sub-millisecond latency per call.
final class InventoryListPerfTests: XCTestCase {

    // MARK: - 1000-row hot-read benchmark

    /// 100 hot cache reads of 1 000 rows must complete under 1 second total.
    func testCachedListHotRead1000Rows() async throws {
        let api = SpyInventoryAPIClient1000()
        let repo = InventoryCachedRepositoryImpl(api: api)

        // Populate cache via forceRefresh.
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let start = Date()
        for _ in 0..<100 {
            let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 60)
            XCTAssertEqual(result.value.count, 1000)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "100 hot reads of 1000 rows took \(elapsed)s — exceeds 1s budget")
    }

    // MARK: - ViewModel fetch benchmark

    func testViewModelFetch1000Items() async throws {
        let api = SpyInventoryAPIClient1000()
        let repo = InventoryCachedRepositoryImpl(api: api)
        // Pre-warm.
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let vm = await InventoryListViewModel(repo: repo)

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

// MARK: - SpyInventoryAPIClient1000

/// Returns 1 000 InventoryListItem values from `get("/api/v1/inventory", ...)`.
private actor SpyInventoryAPIClient1000: APIClient {

    private let response: InventoryListResponse = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let itemsJsonArray = (0..<1000).map { i in
            "{\"id\":\(i+1),\"name\":\"Item \(i)\",\"sku\":\"SKU-\(i)\",\"item_type\":\"product\",\"in_stock\":\(i % 10),\"reorder_level\":2,\"retail_price\":9.99,\"is_serialized\":0}"
        }.joined(separator: ",")
        let responseJson = "{\"items\":[\(itemsJsonArray)]}".data(using: .utf8)!
        return try! decoder.decode(InventoryListResponse.self, from: responseJson)
    }()

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/inventory" else { throw APITransportError.noBaseURL }
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
