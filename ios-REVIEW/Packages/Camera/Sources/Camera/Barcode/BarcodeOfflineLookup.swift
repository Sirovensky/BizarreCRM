import Foundation
import Networking
import Core


// MARK: - BarcodeOfflineLookup
//
// §17.2 Offline lookup:
// 1. Hit local GRDB cache (InventoryBarcodeCache) first.
// 2. If cache miss AND online → server lookup via APIClient.
// 3. If cache miss AND offline → throw BarcodeError.notFound with toast hint.
//
// The cache is written by the Inventory read-surface (§6) during the standard
// GRDB upsert pipeline. This actor reads from that same table and does NOT own
// the write path.

// MARK: - InventoryBarcodeItem bridge

/// Lightweight summary of an inventory item returned by barcode lookup.
/// Bridges `InventoryBarcodeItem` (Networking) into the Camera package
/// without creating a cross-package compile-time dependency cycle.
public struct BarcodeInventoryItem: Sendable {
    public let id: Int64
    public let displayName: String
    public let sku: String?
    public let upc: String?
    public let inStock: Int?
    public let retailPrice: Double?
    public let itemType: String?

    public init(
        id: Int64,
        displayName: String,
        sku: String?,
        upc: String?,
        inStock: Int?,
        retailPrice: Double?,
        itemType: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.sku = sku
        self.upc = upc
        self.inStock = inStock
        self.retailPrice = retailPrice
        self.itemType = itemType
    }
}

// MARK: - BarcodeOfflineLookup

/// Actor that performs offline-first barcode → inventory item lookup.
///
/// Dependency injection: callers supply a `BarcodeNetworkSource` and a `BarcodeCacheReader`.
/// In tests, supply lightweight fakes for both protocols — no real APIClient or database needed.
public actor BarcodeOfflineLookup {

    // MARK: - Cache reader abstraction

    /// Protocol over the GRDB cache so this actor can be unit-tested.
    public protocol BarcodeCacheReader: Sendable {
        /// Look up a barcode value in the local cache.
        /// Returns `nil` when not found.
        func fetchItem(forBarcode code: String) async -> BarcodeInventoryItem?
    }

    // MARK: - Network source abstraction (testable)

    /// Protocol over the network call so this actor can be unit-tested without subclassing APIClient.
    public protocol BarcodeNetworkSource: Sendable {
        func lookupInventoryItem(barcode code: String) async throws -> BarcodeInventoryItem
    }

    // MARK: - Reachability abstraction (testable)

    public protocol ReachabilitySource: Sendable {
        var isOnline: Bool { get async }
    }

    // MARK: - Dependencies

    private let cacheReader: BarcodeCacheReader
    private let api: BarcodeNetworkSource
    private let reachability: ReachabilitySource

    // MARK: - Init

    public init(
        cacheReader: BarcodeCacheReader,
        api: BarcodeNetworkSource,
        reachability: ReachabilitySource
    ) {
        self.cacheReader = cacheReader
        self.api = api
        self.reachability = reachability
    }

    // MARK: - Lookup

    /// Performs offline-first lookup for a barcode value.
    ///
    /// Resolution order:
    /// 1. Local GRDB cache — instant, works fully offline.
    /// 2. Server `GET /api/v1/inventory/barcode/:code` — if online.
    /// 3. `BarcodeError.notFound` if both miss.
    ///
    /// - Parameter code: Raw barcode string (e.g. "850026102152").
    /// - Returns: `BarcodeInventoryItem` with item details.
    /// - Throws: `BarcodeError.notFound` or `BarcodeError.networkError`.
    public func lookup(code: String) async throws -> BarcodeInventoryItem {
        // 1. Try local cache first.
        if let cached = await cacheReader.fetchItem(forBarcode: code) {
            AppLog.ui.info("BarcodeOfflineLookup: cache hit for \(code, privacy: .private)")
            return cached
        }

        // 2. If offline, surface a friendly error.
        let online = await reachability.isOnline
        guard online else {
            AppLog.ui.info("BarcodeOfflineLookup: offline + cache miss for \(code, privacy: .private)")
            throw BarcodeError.notFound(code)
        }

        // 3. Server lookup via BarcodeNetworkSource (concrete: APIClient).
        do {
            let result = try await api.lookupInventoryItem(barcode: code)
            AppLog.ui.info("BarcodeOfflineLookup: server hit for \(code, privacy: .private)")
            return result
        } catch let e as APITransportError {
            if case .httpStatus(404, _) = e {
                throw BarcodeError.notFound(code)
            }
            throw BarcodeError.networkError(e.localizedDescription)
        } catch {
            throw BarcodeError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - APIClient conformance to BarcodeNetworkSource
//
// Declared in Camera (which imports Networking) so the dependency flows
// Camera → Networking only, never the reverse.

extension APIClientImpl: BarcodeOfflineLookup.BarcodeNetworkSource {
    public func lookupInventoryItem(barcode code: String) async throws -> BarcodeInventoryItem {
        let item = try await inventoryItemByBarcode(code)
        return BarcodeInventoryItem(
            id: item.id,
            displayName: item.displayName,
            sku: item.sku,
            upc: item.upc,
            inStock: item.inStock,
            retailPrice: item.retailPrice,
            itemType: item.itemType
        )
    }
}
