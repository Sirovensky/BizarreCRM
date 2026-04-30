#if canImport(UIKit)
import Foundation
import Core
import Networking

// MARK: - PosCatalogOfflineStore (§16.2, §16.12)

/// Local-first catalog cache for the POS.
///
/// **Why this exists:**
/// The catalog (inventory items + pricing) is fetched from the server. When
/// the device is offline, `PosViewModel` must still display the product grid
/// so cashiers can ring up sales without connection. This actor wraps the GRDB
/// (or UserDefaults fallback) persistence layer that `InventoryRepository` feeds
/// into — per §20.5, the actual GRDB plumbing lives in `InventoryRepository`;
/// this store is the POS-specific read/write façade on top of it.
///
/// **Refresh policy (§16.12):**
/// - On each app launch: if the cache is >24 hours old, queue a background
///   refresh from `GET /inventory/items?per_page=500&pos=true`.
/// - `PosCatalogStalenessService` (already shipped) surfaces the amber warning
///   banner when catalog age exceeds 24 h.
/// - On fresh install / first launch: the store is empty; the POS blocks on
///   a network fetch before presenting the catalog.
///
/// **POS-specific fields:**
/// `PosCatalogItem` mirrors the server's inventory item shape but includes
/// only the fields the POS needs (name, sku, price, stock, image URL) to keep
/// the local blob small.
public actor PosCatalogOfflineStore {

    // MARK: - Singleton

    public static let shared = PosCatalogOfflineStore()
    private init() {}

    // MARK: - In-memory cache (backed by UserDefaults MVP)

    private var items: [PosCatalogItem] = []
    private var lastRefreshedAt: Date?

    /// How old the cache can be before the staleness service fires.
    public static let stalenessThreshold: TimeInterval = 24 * 60 * 60  // 24 h

    // MARK: - UserDefaults keys (GRDB wired via §20.5 InventoryRepository)

    private let itemsKey = "pos.catalog.items.v2"
    private let refreshedAtKey = "pos.catalog.refreshedAt"

    // MARK: - Load

    /// Load cached items from persistent storage on first access.
    public func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: itemsKey),
              let decoded = try? JSONDecoder().decode([PosCatalogItem].self, from: data)
        else { return }
        items = decoded
        lastRefreshedAt = UserDefaults.standard.object(forKey: refreshedAtKey) as? Date
    }

    // MARK: - Read

    /// Returns all cached catalog items. If the store has never been loaded,
    /// loads from disk first (synchronous in actor context — fast UserDefaults read).
    public func allItems() -> [PosCatalogItem] {
        if items.isEmpty { loadFromDisk() }
        return items
    }

    /// Text-filter helper for POS search.
    public func items(matching query: String) -> [PosCatalogItem] {
        guard !query.isEmpty else { return allItems() }
        let q = query.lowercased()
        return allItems().filter {
            $0.name.lowercased().contains(q) ||
            ($0.sku?.lowercased().contains(q) ?? false)
        }
    }

    /// Date of the last successful catalog refresh. Drives staleness logic.
    public func catalogAge() -> TimeInterval? {
        guard let last = lastRefreshedAt else { return nil }
        return Date.now.timeIntervalSince(last)
    }

    public var needsRefresh: Bool {
        guard let age = catalogAge() else { return true }
        return age > Self.stalenessThreshold
    }

    // MARK: - Write

    /// Replace the catalog cache with items returned by the server.
    /// Called by `PosRepository.refreshCatalog()` after a successful fetch.
    public func replace(with serverItems: [PosCatalogItem]) {
        items = serverItems
        lastRefreshedAt = .now
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: itemsKey)
        UserDefaults.standard.set(lastRefreshedAt, forKey: refreshedAtKey)
    }
}

// MARK: - PosCatalogItem

/// Lightweight POS-facing representation of a sellable inventory item.
/// Contains only the fields the POS register needs; full item detail is
/// fetched on demand from `GET /inventory/items/:id`.
public struct PosCatalogItem: Identifiable, Codable, Sendable, Hashable {

    public let id: Int64
    public let name: String
    public let sku: String?
    public let unitPriceCents: Int
    public let stockOnHand: Int?
    public let imageURL: URL?
    public let isMemberOnly: Bool
    public let isActive: Bool

    // MARK: - Decoding keys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sku
        case unitPriceCents  = "unit_price_cents"
        case stockOnHand     = "stock_on_hand"
        case imageURL        = "image_url"
        case isMemberOnly    = "is_member_only"
        case isActive        = "is_active"
    }

    public init(
        id: Int64,
        name: String,
        sku: String? = nil,
        unitPriceCents: Int,
        stockOnHand: Int? = nil,
        imageURL: URL? = nil,
        isMemberOnly: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.sku = sku
        self.unitPriceCents = unitPriceCents
        self.stockOnHand = stockOnHand
        self.imageURL = imageURL
        self.isMemberOnly = isMemberOnly
        self.isActive = isActive
    }
}

// MARK: - PosCatalogRefreshService (§16.12 daily refresh)

/// Background service that keeps `PosCatalogOfflineStore` fresh.
///
/// Wire into the POS scene `.onAppear` / `.task` lifecycle.
/// If the catalog is stale (>24 h), triggers a background fetch.
/// On success, replaces the cache. On failure, the existing stale cache
/// remains available and `PosCatalogStalenessService` surfaces the banner.
@MainActor
public final class PosCatalogRefreshService {

    // MARK: - Singleton

    public static let shared = PosCatalogRefreshService()
    private init() {}

    // MARK: - State

    private(set) var isRefreshing = false

    // MARK: - Refresh

    /// Triggers a catalog refresh if the cache is stale or empty.
    /// Safe to call on every `PosView.task{}` — no-ops when fresh.
    public func refreshIfNeeded(api: APIClient?) async {
        guard !isRefreshing else { return }
        let needsRefresh = await PosCatalogOfflineStore.shared.needsRefresh
        guard needsRefresh, let api else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await api.listPosCatalogItems()
            await PosCatalogOfflineStore.shared.replace(with: response)
            AppLog.pos.info("POS catalog refreshed: \(response.count) items")
        } catch {
            // Non-fatal: stale cache remains usable; staleness banner shown.
            AppLog.pos.warning("POS catalog refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - APIClient extension

private extension APIClient {
    /// `GET /api/v1/inventory/items?pos=true&per_page=500`
    /// Returns the POS-optimised catalog (active items only, with pricing).
    /// Server: `packages/server/src/routes/inventory.ts` — `GET /inventory/items`.
    func listPosCatalogItems() async throws -> [PosCatalogItem] {
        try await get(
            "/api/v1/inventory/items",
            query: [
                URLQueryItem(name: "pos", value: "true"),
                URLQueryItem(name: "per_page", value: "500"),
                URLQueryItem(name: "is_active", value: "true")
            ],
            as: [PosCatalogItem].self
        )
    }
}
#endif
