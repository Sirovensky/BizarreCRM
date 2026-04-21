import Foundation
import Networking
import Core

// MARK: - CustomerCachedRepository

/// Extends `CustomerRepository` with caching primitives for `CustomerListView`.
public protocol CustomerCachedRepository: CustomerRepository {
    /// When the list was last successfully fetched from the server.
    var lastSyncedAt: Date? { get async }

    /// Bypass the cache and fetch fresh data. Called on pull-to-refresh.
    func forceRefresh(keyword: String?) async throws -> [CustomerSummary]
}

// MARK: - CustomerCachedRepositoryImpl

/// Wraps any `CustomerRepository` with a per-keyword in-memory cache.
///
/// Strategy:
/// - `list(keyword:)` returns cached data if within `maxAgeSeconds`;
///   otherwise fetches from remote and caches.
/// - `forceRefresh(keyword:)` always hits remote (pull-to-refresh).
/// - Cache is keyed by `keyword ?? ""`.
///
/// TODO(phase-4): Persist cache to GRDB for instant cold-launch data.
public actor CustomerCachedRepositoryImpl: CustomerCachedRepository {

    // MARK: - Cache entry

    private struct CacheEntry {
        let customers: [CustomerSummary]
        let fetchedAt: Date
    }

    // MARK: - State

    private let remote: CustomerRepository
    private let maxAgeSeconds: Int
    private var cache: [String: CacheEntry] = [:]
    private var latestSyncedAt: Date?

    // MARK: - Init

    public init(remote: CustomerRepository, maxAgeSeconds: Int = 120) {
        self.remote = remote
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - CustomerCachedRepository

    public var lastSyncedAt: Date? { latestSyncedAt }

    /// Returns cache if fresh; else fetches and caches.
    public func list(keyword: String?) async throws -> [CustomerSummary] {
        let key = keyword ?? ""
        if let entry = cache[key] {
            let age = Date().timeIntervalSince(entry.fetchedAt)
            if age <= Double(maxAgeSeconds) {
                return entry.customers
            }
        }
        return try await fetch(keyword: keyword, key: key)
    }

    /// Always fetches from remote. Used by pull-to-refresh.
    public func forceRefresh(keyword: String?) async throws -> [CustomerSummary] {
        let key = keyword ?? ""
        return try await fetch(keyword: keyword, key: key)
    }

    // MARK: - Private

    private func fetch(keyword: String?, key: String) async throws -> [CustomerSummary] {
        let customers = try await remote.list(keyword: keyword)
        let now = Date()
        cache[key] = CacheEntry(customers: customers, fetchedAt: now)
        latestSyncedAt = now
        return customers
    }
}
