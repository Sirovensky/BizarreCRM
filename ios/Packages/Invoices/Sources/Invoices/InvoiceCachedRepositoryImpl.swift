import Foundation
import Core
import Networking
import Sync

// MARK: - InvoiceCacheFilter

/// Composite cache key combining filter + keyword.
struct InvoiceCacheFilter: Sendable, Hashable {
    let filter: InvoiceFilter
    let keyword: String?
    let sort: InvoiceSortOption?
    let statusTab: InvoiceStatusTab?

    init(filter: InvoiceFilter, keyword: String?, sort: InvoiceSortOption? = nil, statusTab: InvoiceStatusTab? = nil) {
        self.filter = filter
        self.keyword = keyword
        self.sort = sort
        self.statusTab = statusTab
    }
}

// MARK: - InvoiceCachedRepositoryImpl

/// Write-through in-memory cache wrapping `InvoiceRepositoryImpl`.
///
/// Satisfies the `InvoiceRepository` protocol. Returns cached data immediately;
/// triggers a background remote refresh when stale.
///
/// TODO(phase-3-followup): replace in-memory store with GRDB ValueObservation
/// once the Invoices GRDB DAO is wired (§20).
public actor InvoiceCachedRepositoryImpl: InvoiceRepository {

    // MARK: - State

    private let underlying: InvoiceRepositoryImpl
    private var cache: [InvoiceCacheFilter: [InvoiceSummary]] = [:]
    private var syncedAt: [InvoiceCacheFilter: Date] = [:]
    private var _lastSyncedAt: Date?

    // BUGHUNT-2026-05-17: per-key inflight tracker so rapid status-tab switches
    // + scroll + pull-to-refresh don't fan out into N concurrent /invoices
    // fetches with the last-arriving response winning the cache write. Used
    // for both `listExtended` (status-tab sort) and `cachedList` (legacy
    // filter) refresh shapes — they key off different cache keys. Same
    // fix family as EstimateCachedRepositoryImpl / InventoryCachedRepositoryImpl.
    private var refreshInflight: [InvoiceCacheFilter: Task<Void, Never>] = [:]

    // MARK: - Init

    public init(api: APIClient) {
        self.underlying = InvoiceRepositoryImpl(api: api)
    }

    // MARK: - InvoiceRepository conformance (legacy plain list)

    public func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        let result = try await cachedList(filter: filter, keyword: keyword, maxAgeSeconds: 300)
        return result.value
    }

    public func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?,
        advancedFilter: InvoiceListFilter
    ) async throws -> InvoicesListResponse {
        // Cursor fetches bypass cache (they're paginated)
        if cursor != nil {
            return try await underlying.listExtended(statusTab: statusTab, keyword: keyword, sort: sort, cursor: cursor, advancedFilter: advancedFilter)
        }
        let key = InvoiceCacheFilter(filter: statusTab.legacyFilter, keyword: keyword, sort: sort, statusTab: statusTab)
        let cached = cache[key] ?? []
        let lastSync = syncedAt[key]
        let isStale: Bool
        if let lastSync {
            isStale = Date().timeIntervalSince(lastSync) > 300
        } else {
            isStale = true
        }
        if isStale, refreshInflight[key] == nil {
            let task = Task<Void, Never> { [statusTab, keyword, sort, advancedFilter, key] in
                await self.runExtendedRefresh(
                    statusTab: statusTab, keyword: keyword, sort: sort,
                    advancedFilter: advancedFilter, key: key
                )
            }
            refreshInflight[key] = task
        }
        return InvoicesListResponse(invoices: cached, pagination: nil)
    }

    // MARK: - CachedResult list

    /// Main read surface. Returns cached data immediately; triggers background
    /// refresh when the cache is stale.
    public func cachedList(
        filter: InvoiceFilter,
        keyword: String?,
        maxAgeSeconds: Int = 300
    ) async throws -> CachedResult<[InvoiceSummary]> {
        let key = InvoiceCacheFilter(filter: filter, keyword: keyword)
        let cached = cache[key] ?? []
        let lastSync = syncedAt[key]

        let isStale: Bool
        if let lastSync {
            isStale = Date().timeIntervalSince(lastSync) > Double(maxAgeSeconds)
        } else {
            isStale = true
        }

        if isStale, refreshInflight[key] == nil {
            let task = Task<Void, Never> { [filter, keyword, key] in
                await self.runListRefresh(filter: filter, keyword: keyword, key: key)
            }
            refreshInflight[key] = task
        }

        return CachedResult(
            value: cached,
            source: isStale ? .cache : .cache,
            lastSyncedAt: lastSync,
            isStale: isStale
        )
    }

    // MARK: - Force refresh

    public func forceRefresh(filter: InvoiceFilter, keyword: String?) async throws -> CachedResult<[InvoiceSummary]> {
        let key = InvoiceCacheFilter(filter: filter, keyword: keyword)
        let fresh = try await underlying.list(filter: filter, keyword: keyword)
        updateCache(key: key, items: fresh)
        return CachedResult(
            value: fresh,
            source: .remote,
            lastSyncedAt: _lastSyncedAt,
            isStale: false
        )
    }

    /// Invalidate a specific filter's cache entry (e.g., after a write).
    public func invalidate(filter: InvoiceFilter, keyword: String?) {
        let key = InvoiceCacheFilter(filter: filter, keyword: keyword)
        syncedAt.removeValue(forKey: key)
    }

    // MARK: - lastSyncedAt accessor

    public var lastSyncedAt: Date? { _lastSyncedAt }

    // MARK: - Private

    private func updateCache(key: InvoiceCacheFilter, items: [InvoiceSummary]) {
        let now = Date()
        cache[key] = items
        syncedAt[key] = now
        _lastSyncedAt = now
    }

    /// Background refresh body for the extended/status-tab list shape.
    private func runExtendedRefresh(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        advancedFilter: InvoiceListFilter,
        key: InvoiceCacheFilter
    ) async {
        defer { refreshInflight[key] = nil }
        do {
            let fresh = try await underlying.listExtended(
                statusTab: statusTab, keyword: keyword, sort: sort,
                cursor: nil, advancedFilter: advancedFilter
            )
            updateCache(key: key, items: fresh.invoices)
        } catch {
            AppLog.sync.warning("Invoices extended refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Background refresh body for the legacy plain-list shape.
    private func runListRefresh(
        filter: InvoiceFilter,
        keyword: String?,
        key: InvoiceCacheFilter
    ) async {
        defer { refreshInflight[key] = nil }
        do {
            let fresh = try await underlying.list(filter: filter, keyword: keyword)
            updateCache(key: key, items: fresh)
        } catch {
            AppLog.sync.warning("Invoices background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
