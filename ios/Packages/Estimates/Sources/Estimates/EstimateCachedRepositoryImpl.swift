import Foundation
import Core
import Networking
import Sync

// MARK: - EstimateCachedRepositoryImpl

/// Write-through in-memory cache wrapping `EstimateRepositoryImpl`.
///
/// Conforms to `EstimateRepository` — drop-in replacement for the direct API
/// call path. Returns cached data immediately; triggers a background remote
/// refresh when stale.
///
/// TODO(phase-3-followup): replace in-memory store with GRDB ValueObservation
/// once the Estimates GRDB DAO is wired (§20).
public actor EstimateCachedRepositoryImpl: EstimateRepository {

    // MARK: - State

    private let underlying: EstimateRepositoryImpl
    private var cache: [String?: [Estimate]] = [:]
    private var syncedAt: [String?: Date] = [:]
    private var _lastSyncedAt: Date?

    // MARK: - Init

    public init(api: APIClient) {
        self.underlying = EstimateRepositoryImpl(api: api)
    }

    // MARK: - EstimateRepository conformance

    public func list(keyword: String?) async throws -> [Estimate] {
        let result = try await cachedList(keyword: keyword, maxAgeSeconds: 300)
        return result.value
    }

    /// Cursor pages always go through the underlying repo (no cursor-aware cache for MVP).
    public func listPage(
        status: EstimateStatusFilter,
        keyword: String?,
        cursor: String?
    ) async throws -> EstimatePageResult {
        try await underlying.listPage(status: status, keyword: keyword, cursor: cursor)
    }

    // MARK: - CachedResult list

    public func cachedList(
        keyword: String?,
        maxAgeSeconds: Int = 300
    ) async throws -> CachedResult<[Estimate]> {
        let cached = cache[keyword] ?? []
        let lastSync = syncedAt[keyword]

        let isStale: Bool
        if let lastSync {
            isStale = Date().timeIntervalSince(lastSync) > Double(maxAgeSeconds)
        } else {
            isStale = true
        }

        if isStale {
            Task {
                do {
                    let fresh = try await self.underlying.list(keyword: keyword)
                    await self.updateCache(keyword: keyword, items: fresh)
                } catch {
                    AppLog.sync.warning("Estimates background refresh failed: \(error.localizedDescription, privacy: .public)")
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

    public func forceRefresh(keyword: String?) async throws -> CachedResult<[Estimate]> {
        let fresh = try await underlying.list(keyword: keyword)
        updateCache(keyword: keyword, items: fresh)
        return CachedResult(
            value: fresh,
            source: .remote,
            lastSyncedAt: _lastSyncedAt,
            isStale: false
        )
    }

    // MARK: - lastSyncedAt accessor

    public var lastSyncedAt: Date? { _lastSyncedAt }

    // MARK: - Private

    private func updateCache(keyword: String?, items: [Estimate]) {
        let now = Date()
        cache[keyword] = items
        syncedAt[keyword] = now
        _lastSyncedAt = now
    }
}
