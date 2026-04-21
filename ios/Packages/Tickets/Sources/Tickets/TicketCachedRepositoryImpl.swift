import Foundation
import Networking
import Core

// MARK: - TicketCachedRepository

/// Extends `TicketRepository` with caching primitives consumed by `TicketListView`.
public protocol TicketCachedRepository: TicketRepository {
    /// When the list was last successfully fetched from the server.
    var lastSyncedAt: Date? { get async }

    /// Bypass the cache and fetch fresh data. Called on pull-to-refresh.
    func forceRefresh(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary]
}

// MARK: - TicketCachedRepositoryImpl

/// Wraps any `TicketRepository` with a per-(filter, keyword) in-memory cache.
///
/// Strategy:
/// - `list(filter:keyword:)` returns cached data if within `maxAgeSeconds`;
///   otherwise fetches from remote and caches result.
/// - `forceRefresh(filter:keyword:)` always hits remote (pull-to-refresh).
/// - Cache keyed by `(filter, keyword ?? "")` — cheap and correct for MVP.
///
/// TODO(phase-4): Replace in-memory cache with GRDB persistence so cold
/// launches get instant data without a network round-trip.
public actor TicketCachedRepositoryImpl: TicketCachedRepository {

    // MARK: - Cache entry

    private struct CacheEntry {
        let tickets: [TicketSummary]
        let fetchedAt: Date
    }

    // MARK: - State

    private let remote: TicketRepository
    private let maxAgeSeconds: Int
    private var cache: [String: CacheEntry] = [:]
    private var latestSyncedAt: Date?

    // MARK: - Init

    public init(remote: TicketRepository, maxAgeSeconds: Int = 120) {
        self.remote = remote
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - TicketCachedRepository

    public var lastSyncedAt: Date? { latestSyncedAt }

    /// Returns cache if fresh; else fetches and caches.
    public func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        let key = cacheKey(filter: filter, keyword: keyword)
        if let entry = cache[key] {
            let age = Date().timeIntervalSince(entry.fetchedAt)
            if age <= Double(maxAgeSeconds) {
                return entry.tickets
            }
        }
        return try await fetch(filter: filter, keyword: keyword, key: key)
    }

    /// Always fetches from remote. Used by pull-to-refresh.
    public func forceRefresh(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        let key = cacheKey(filter: filter, keyword: keyword)
        return try await fetch(filter: filter, keyword: keyword, key: key)
    }

    /// Pass-through — detail view calls this directly; no caching needed for MVP.
    public func detail(id: Int64) async throws -> TicketDetail {
        try await remote.detail(id: id)
    }

    // MARK: - Private

    private func cacheKey(filter: TicketListFilter, keyword: String?) -> String {
        "\(filter.rawValue)|\(keyword ?? "")"
    }

    private func fetch(filter: TicketListFilter, keyword: String?, key: String) async throws -> [TicketSummary] {
        let tickets = try await remote.list(filter: filter, keyword: keyword)
        let now = Date()
        cache[key] = CacheEntry(tickets: tickets, fetchedAt: now)
        latestSyncedAt = now
        return tickets
    }
}
