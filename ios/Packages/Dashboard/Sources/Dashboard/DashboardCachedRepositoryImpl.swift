import Foundation
import Core

// MARK: - DashboardCachedRepository

/// Protocol extending `DashboardRepository` with staleness information so
/// views can show a `StalenessIndicator` and force-refresh on pull-to-refresh.
public protocol DashboardCachedRepository: DashboardRepository {
    /// When the snapshot was last successfully loaded from the server.
    var lastSyncedAt: Date? { get async }

    /// Bypass the cache and fetch fresh data from the server.
    func forceRefresh() async throws -> DashboardSnapshot
}

// MARK: - DashboardCachedRepositoryImpl

/// Wraps any `DashboardRepository` with an in-memory cache + timestamp.
///
/// Strategy:
/// - `load()` returns cached data immediately if within `maxAgeSeconds`.
///   Otherwise it fetches from the remote and updates the cache.
/// - `forceRefresh()` always hits the remote (used by pull-to-refresh).
/// - Cache is in-memory (`actor`-isolated); GRDB persistence is a follow-up TODO.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches also get instant data.
public actor DashboardCachedRepositoryImpl: DashboardCachedRepository {

    // MARK: - Constants

    private let maxAgeSeconds: Int

    // MARK: - Injected

    private let remote: DashboardRepository

    // MARK: - In-memory cache

    private var cachedSnapshot: DashboardSnapshot?
    private var cacheTimestamp: Date?

    // MARK: - Init

    public init(remote: DashboardRepository, maxAgeSeconds: Int = 300) {
        self.remote = remote
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - DashboardCachedRepository

    public var lastSyncedAt: Date? { cacheTimestamp }

    /// Returns cached snapshot if fresh; otherwise fetches and caches.
    public func load() async throws -> DashboardSnapshot {
        if let snapshot = cachedSnapshot, let ts = cacheTimestamp {
            let age = Date().timeIntervalSince(ts)
            if age <= Double(maxAgeSeconds) {
                return snapshot
            }
        }
        return try await fetchAndCache()
    }

    /// Always hits the remote. Called by pull-to-refresh.
    public func forceRefresh() async throws -> DashboardSnapshot {
        try await fetchAndCache()
    }

    // MARK: - Private

    private func fetchAndCache() async throws -> DashboardSnapshot {
        let snapshot = try await remote.load()
        cachedSnapshot = snapshot
        cacheTimestamp = Date()
        return snapshot
    }
}
