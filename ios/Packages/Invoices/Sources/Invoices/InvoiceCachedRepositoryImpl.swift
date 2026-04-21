import Foundation
import Core
import Networking
import Sync

// MARK: - InvoiceCacheFilter

/// Composite cache key combining filter + keyword.
struct InvoiceCacheFilter: Sendable, Hashable {
    let filter: InvoiceFilter
    let keyword: String?
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

    // MARK: - Init

    public init(api: APIClient) {
        self.underlying = InvoiceRepositoryImpl(api: api)
    }

    // MARK: - InvoiceRepository conformance (legacy plain list)

    public func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        let result = try await cachedList(filter: filter, keyword: keyword, maxAgeSeconds: 300)
        return result.value
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

        if isStale {
            Task {
                do {
                    let fresh = try await self.underlying.list(filter: filter, keyword: keyword)
                    await self.updateCache(key: key, items: fresh)
                } catch {
                    AppLog.sync.warning("Invoices background refresh failed: \(error.localizedDescription, privacy: .public)")
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
}
