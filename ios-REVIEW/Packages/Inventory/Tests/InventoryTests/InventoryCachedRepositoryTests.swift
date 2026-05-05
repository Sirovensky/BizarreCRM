import XCTest
@testable import Inventory
import Networking
import Sync

// MARK: - InventoryCachedRepositoryTests

/// Unit tests for `InventoryCachedRepositoryImpl`.
/// Coverage: cache miss, cache hit, staleness, forceRefresh, invalidate.
final class InventoryCachedRepositoryTests: XCTestCase {

    // MARK: - Cold read (cache miss) is stale

    func testColdReadIsStale() async throws {
        let api = SpyInventoryAPIClient(items: [])
        let repo = InventoryCachedRepositoryImpl(api: api)

        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)

        // Cold read: cache empty → isStale = true, value is empty initially.
        XCTAssertTrue(result.isStale)
        XCTAssertNil(result.lastSyncedAt)
        XCTAssertTrue(result.value.isEmpty)
    }

    // MARK: - Force refresh populates cache

    func testForceRefreshPopulatesCache() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1), sampleItem(id: 2)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(filter: .all, keyword: nil)

        XCTAssertEqual(result.value.count, 2)
        XCTAssertEqual(result.source, .remote)
        XCTAssertFalse(result.isStale)
        XCTAssertNotNil(result.lastSyncedAt)
    }

    // MARK: - Hot read after force refresh is not stale

    func testHotReadAfterRefreshIsNotStale() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        // Immediately read again with large maxAge → should be fresh.
        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)

        XCTAssertFalse(result.isStale)
        XCTAssertEqual(result.value.count, 1)
        XCTAssertNotNil(result.lastSyncedAt)
    }

    // MARK: - Expired cache is stale

    func testExpiredCacheIsStale() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        // maxAgeSeconds = 0 → always stale.
        let result = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 0)

        XCTAssertTrue(result.isStale)
    }

    // MARK: - Invalidate clears the timestamp

    func testInvalidateMakesCacheStale() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        // Verify it's hot.
        let hotResult = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)
        XCTAssertFalse(hotResult.isStale)

        // Invalidate.
        await repo.invalidate(filter: .all, keyword: nil)

        // Now a hot read should be stale (no timestamp).
        let staleResult = try await repo.cachedList(filter: .all, keyword: nil, maxAgeSeconds: 300)
        XCTAssertTrue(staleResult.isStale)
    }

    // MARK: - lastSyncedAt exposed

    func testLastSyncedAtUpdatedAfterRefresh() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        let beforeRefresh = await repo.lastSyncedAt
        XCTAssertNil(beforeRefresh)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let afterRefresh = await repo.lastSyncedAt
        XCTAssertNotNil(afterRefresh)
    }

    // MARK: - Different filter keys are cached independently

    func testDifferentFiltersHaveIndependentCaches() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        // Low stock key is still cold.
        let lowStockResult = try await repo.cachedList(filter: .lowStock, keyword: nil, maxAgeSeconds: 300)
        XCTAssertTrue(lowStockResult.isStale)
    }

    // MARK: - Legacy list() delegates through cached path

    func testLegacyListDelegates() async throws {
        let api = SpyInventoryAPIClient(items: [])
        let repo = InventoryCachedRepositoryImpl(api: api)

        // list() returns empty array on cold cache without throwing.
        let items = try await repo.list(filter: .all, keyword: nil)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - CachedResult staleness reflects lastSyncedAt correctly

    func testStalenessLevelMatchesLastSyncedAt() async throws {
        let api = SpyInventoryAPIClient(items: [sampleItem(id: 1)])
        let repo = InventoryCachedRepositoryImpl(api: api)

        let result = try await repo.forceRefresh(filter: .all, keyword: nil)

        XCTAssertNotNil(result.lastSyncedAt)
        XCTAssertFalse(result.isStale)
    }

    // MARK: - Helpers

    private func sampleItem(id: Int64) -> InventoryListItem {
        // Use JSON decoding to construct the model correctly (CodingKeys-based).
        let json = """
        {
            "id": \(id),
            "name": "Item \(id)",
            "sku": "SKU-\(id)",
            "item_type": "product",
            "in_stock": 5,
            "reorder_level": 2,
            "retail_price": 10.0,
            "is_serialized": 0
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(InventoryListItem.self, from: json)
    }
}

// MARK: - SpyInventoryAPIClient

/// Intercepts `get("/api/v1/inventory", ...)` calls to return canned data.
/// The `listInventory` extension on `APIClient` calls `self.get(...)`, so we
/// implement `get<T>` to return the fixture.
private actor SpyInventoryAPIClient: APIClient {
    let items: [InventoryListItem]
    private(set) var listCallCount = 0

    init(items: [InventoryListItem]) {
        self.items = items
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        guard path == "/api/v1/inventory" else { throw APITransportError.noBaseURL }
        listCallCount += 1
        // Build items JSON array, then wrap in InventoryListResponse envelope.
        var itemsJson = items.map { item in
            "{\"id\":\(item.id),\"name\":\(jsonString(item.name ?? "null")),\"sku\":\(jsonString(item.sku ?? "null")),\"item_type\":\(jsonString(item.itemType ?? "null")),\"in_stock\":\(item.inStock ?? 0),\"reorder_level\":\(item.reorderLevel ?? 0),\"retail_price\":9.99,\"is_serialized\":0}"
        }.joined(separator: ",")
        let responseJson = "{\"items\":[\(itemsJson)]}".data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(InventoryListResponse.self, from: responseJson)
        guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    private nonisolated func jsonString(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
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
