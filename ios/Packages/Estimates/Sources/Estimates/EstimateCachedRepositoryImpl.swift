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
    // BUGHUNT-2026-05-17: per-key inflight tracker so rapid scroll / repeated
    // cachedList calls don't fan out into N concurrent /estimates fetches.
    // Without this, the last-arriving response won the cache write, masking
    // an earlier (correct) response and forcing the UI to render stale rows
    // when the user scrolled through filters quickly. Same fix family as
    // TicketCachedRepositoryImpl/CustomerCachedRepositoryImpl — adapted for
    // the fire-and-forget refresh shape (callers don't await the Task).
    private var refreshInflight: [String?: Task<Void, Never>] = [:]

    // MARK: - Init

    public init(api: APIClient) {
        self.underlying = EstimateRepositoryImpl(api: api)
    }

    // MARK: - EstimateRepository conformance

    public func list(keyword: String?) async throws -> [Estimate] {
        let result = try await cachedList(keyword: keyword, maxAgeSeconds: 300)
        return result.value
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

        if isStale, refreshInflight[keyword] == nil {
            let task = Task<Void, Never> { [keyword] in
                await self.runRefresh(keyword: keyword)
            }
            refreshInflight[keyword] = task
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

    // MARK: - §8.1 Cursor-based pagination

    /// Delegates directly to the underlying API — cursor pages are not cached
    /// in-memory because each page is unique. GRDB caching is a Phase-4 followup.
    public func listPage(cursor: String?, keyword: String?, status: String?) async throws -> EstimatesCursorPage {
        try await underlying.listPage(cursor: cursor, keyword: keyword, status: status)
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

    /// Actor-isolated background refresh body. Factored out so the Task in
    /// `cachedList` can be a plain `@Sendable` closure that hops onto the
    /// actor here. Clears `refreshInflight[keyword]` before returning whether
    /// the network call succeeded or failed.
    private func runRefresh(keyword: String?) async {
        defer { refreshInflight[keyword] = nil }
        do {
            let fresh = try await underlying.list(keyword: keyword)
            updateCache(keyword: keyword, items: fresh)
        } catch {
            AppLog.sync.warning("Estimates background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
