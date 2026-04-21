import Foundation
import Core
import Networking
import Sync

// MARK: - InventoryCacheFilter

/// Composite cache key combining filter + keyword.
struct InventoryCacheFilter: Sendable, Hashable {
    let filter: InventoryFilter
    let keyword: String?
}

// MARK: - InventoryCachedRepositoryImpl

/// Write-through in-memory cache wrapping `InventoryRepositoryImpl`.
///
/// Satisfies `CachedRepository` for the Inventory domain. Returns
/// `CachedResult<[InventoryListItem]>` from every `list(…)` call.
///
/// - Cache hit: items served from in-memory store if within `maxAgeSeconds`.
/// - Cache miss / stale: delegates to the underlying `InventoryRepositoryImpl`
///   and refreshes the store.
///
/// TODO(phase-3-followup): replace in-memory store with GRDB ValueObservation
/// once the Inventory GRDB DAO is wired (§20).
public actor InventoryCachedRepositoryImpl: InventoryRepository {

    // MARK: - State

    private let underlying: InventoryRepositoryImpl
    private var cache: [InventoryCacheFilter: [InventoryListItem]] = [:]
    private var syncedAt: [InventoryCacheFilter: Date] = [:]

    // Expose staleness data to the ViewModel (read on MainActor via await).
    private var _lastSyncedAt: Date?

    // MARK: - Init

    public init(api: APIClient) {
        self.underlying = InventoryRepositoryImpl(api: api)
    }

    // MARK: - InventoryRepository conformance (legacy plain list)

    public func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] {
        let result = try await cachedList(filter: filter, keyword: keyword, maxAgeSeconds: 300)
        return result.value
    }

    // MARK: - CachedResult list

    /// Main read surface. Returns cached data immediately; triggers background
    /// refresh when the cache is stale.
    public func cachedList(
        filter: InventoryFilter,
        keyword: String?,
        maxAgeSeconds: Int = 300
    ) async throws -> CachedResult<[InventoryListItem]> {
        let key = InventoryCacheFilter(filter: filter, keyword: keyword)
        let cached = cache[key] ?? []
        let lastSync = syncedAt[key]

        let isStale: Bool
        if let lastSync {
            isStale = Date().timeIntervalSince(lastSync) > Double(maxAgeSeconds)
        } else {
            isStale = true
        }

        if isStale {
            // Background refresh — best effort; UI already has stale data.
            Task {
                do {
                    let fresh = try await self.underlying.list(filter: filter, keyword: keyword)
                    await self.updateCache(key: key, items: fresh)
                } catch {
                    AppLog.sync.warning("Inventory background refresh failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        return CachedResult(
            value: cached,
            source: isStale ? .cache : .cache,
            lastSyncedAt: lastSync,
            isStale: isStale
        )
    }

    // MARK: - Cache mutations (called from write paths on success)

    /// Force a remote fetch and update the cache for all cached keys.
    /// Called by `InventoryListViewModel.refresh()`.
    public func forceRefresh(filter: InventoryFilter, keyword: String?) async throws -> CachedResult<[InventoryListItem]> {
        let key = InventoryCacheFilter(filter: filter, keyword: keyword)
        let fresh = try await underlying.list(filter: filter, keyword: keyword)
        updateCache(key: key, items: fresh)
        return CachedResult(
            value: fresh,
            source: .remote,
            lastSyncedAt: _lastSyncedAt,
            isStale: false
        )
    }

    /// Called after successful create/update/delete to invalidate affected key.
    public func invalidate(filter: InventoryFilter, keyword: String?) {
        let key = InventoryCacheFilter(filter: filter, keyword: keyword)
        syncedAt.removeValue(forKey: key)
    }

    // MARK: - lastSyncedAt accessor

    public var lastSyncedAt: Date? { _lastSyncedAt }

    // MARK: - Private

    private func updateCache(key: InventoryCacheFilter, items: [InventoryListItem]) {
        let now = Date()
        cache[key] = items
        syncedAt[key] = now
        _lastSyncedAt = now
    }
}
