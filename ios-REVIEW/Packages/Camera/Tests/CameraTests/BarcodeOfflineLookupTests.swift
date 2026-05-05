import XCTest
@testable import Camera

// MARK: - BarcodeOfflineLookupTests

/// Tests for §17.2 offline-first barcode lookup.
final class BarcodeOfflineLookupTests: XCTestCase {

    // MARK: - Fakes

    private final class HitCacheReader: BarcodeOfflineLookup.BarcodeCacheReader, Sendable {
        let item: BarcodeInventoryItem
        init(item: BarcodeInventoryItem) { self.item = item }
        func fetchItem(forBarcode code: String) async -> BarcodeInventoryItem? { item }
    }

    private final class MissCacheReader: BarcodeOfflineLookup.BarcodeCacheReader, Sendable {
        func fetchItem(forBarcode code: String) async -> BarcodeInventoryItem? { nil }
    }

    private struct OnlineSource: BarcodeOfflineLookup.ReachabilitySource, Sendable {
        var isOnline: Bool { get async { true } }
    }

    private struct OfflineSource: BarcodeOfflineLookup.ReachabilitySource, Sendable {
        var isOnline: Bool { get async { false } }
    }

    private static let sampleItem = BarcodeInventoryItem(
        id: 42,
        displayName: "USB Cable",
        sku: "CAB-001",
        upc: "850026102152",
        inStock: 10,
        retailPrice: 9.99,
        itemType: "part"
    )

    // MARK: - Cache hit

    func test_lookup_cacheHit_returnsCachedItem_withoutNetwork() async throws {
        let sut = BarcodeOfflineLookup(
            cacheReader: HitCacheReader(item: Self.sampleItem),
            api: MockNetworkSource(),
            reachability: OfflineSource()   // offline — but cache provides the result
        )
        let result = try await sut.lookup(code: "850026102152")
        XCTAssertEqual(result.id, 42)
        XCTAssertEqual(result.displayName, "USB Cable")
    }

    func test_lookup_cacheHit_doesNotCallNetwork() async throws {
        let mock = MockNetworkSource()
        let sut = BarcodeOfflineLookup(
            cacheReader: HitCacheReader(item: Self.sampleItem),
            api: mock,
            reachability: OnlineSource()
        )
        _ = try await sut.lookup(code: "850026102152")
        // Expect zero network calls when cache hits.
        XCTAssertFalse(mock.wasCalled, "Network must not be called on cache hit")
    }

    // MARK: - Offline cache miss

    func test_lookup_offlineCacheMiss_throwsNotFound() async {
        let sut = BarcodeOfflineLookup(
            cacheReader: MissCacheReader(),
            api: MockNetworkSource(),
            reachability: OfflineSource()
        )
        do {
            _ = try await sut.lookup(code: "UNKNOWN")
            XCTFail("Expected BarcodeError.notFound")
        } catch BarcodeError.notFound(let code) {
            XCTAssertEqual(code, "UNKNOWN")
        } catch {
            XCTFail("Expected BarcodeError.notFound, got \(error)")
        }
    }
}

// MARK: - MockNetworkSource stub

/// Protocol-based mock — no APIClient subclassing required.
private final class MockNetworkSource: BarcodeOfflineLookup.BarcodeNetworkSource, @unchecked Sendable {
    var wasCalled = false

    func lookupInventoryItem(barcode code: String) async throws -> BarcodeInventoryItem {
        wasCalled = true
        throw BarcodeError.notFound(code)
    }
}
