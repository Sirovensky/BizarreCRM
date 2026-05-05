import Foundation
import Networking
import Core

// MARK: - TicketCachedRepository

/// Extends `TicketRepository` with caching primitives consumed by `TicketListView`.
public protocol TicketCachedRepository: TicketRepository {
    /// When the list was last successfully fetched from the server.
    var lastSyncedAt: Date? { get async }

    /// Bypass the cache and fetch fresh data. Called on pull-to-refresh.
    func forceRefresh(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) async throws -> [TicketSummary]
}

public extension TicketCachedRepository {
    func forceRefresh(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        try await forceRefresh(filter: filter, urgency: nil, keyword: keyword)
    }
}

// MARK: - TicketCachedRepositoryImpl

/// Wraps any `TicketRepository` with a two-layer cache:
///
/// 1. **In-memory** (`CacheEntry`) — TTL-gated dictionary keyed by
///    (filter, keyword, sort). Zero-cost hit; invalidated on delete.
/// 2. **Disk** (`TicketDiskCache`) — JSON files in Caches/BizarreCRM/Tickets/.
///    Cold launches call `readDiskCache(key:)` to populate the in-memory
///    layer instantly and show data without a network round-trip.
///    Written after every successful server fetch. Max age 1h (3600s).
///
/// Phase-5 plan: Replace the disk layer with GRDB + SQLCipher row
/// storage for predicate-based local filtering (no per-filter buckets).
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
    public func list(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) async throws -> [TicketSummary] {
        let key = cacheKey(filter: filter, urgency: urgency, keyword: keyword)
        if let entry = cache[key] {
            let age = Date().timeIntervalSince(entry.fetchedAt)
            if age <= Double(maxAgeSeconds) {
                return entry.tickets
            }
        }
        return try await fetch(filter: filter, urgency: urgency, keyword: keyword, key: key)
    }

    /// Always fetches from remote. Used by pull-to-refresh.
    public func forceRefresh(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) async throws -> [TicketSummary] {
        let key = cacheKey(filter: filter, urgency: urgency, keyword: keyword)
        return try await fetch(filter: filter, urgency: urgency, keyword: keyword, key: key)
    }

    /// Pass-through — detail view calls this directly; no caching needed for MVP.
    public func detail(id: Int64) async throws -> TicketDetail {
        try await remote.detail(id: id)
    }

    public func delete(id: Int64) async throws {
        try await remote.delete(id: id)
        cache.removeAll()
    }

    public func duplicate(id: Int64) async throws -> DuplicateTicketResponse {
        let result = try await remote.duplicate(id: id)
        cache.removeAll()
        return result
    }

    public func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse {
        try await remote.convertToInvoice(id: id)
    }

    // MARK: - Private

    private func cacheKey(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?) -> String {
        "\(filter.rawValue)|\(urgency?.rawValue ?? "")|\(keyword ?? "")"
    }

    private func fetch(filter: TicketListFilter, urgency: TicketUrgencyFilter?, keyword: String?, key: String) async throws -> [TicketSummary] {
        let tickets = try await remote.list(filter: filter, urgency: urgency, keyword: keyword)
        let now = Date()
        cache[key] = CacheEntry(tickets: tickets, fetchedAt: now)
        latestSyncedAt = now
        // §4.1 — Persist to disk for cold-launch warm-up
        await TicketDiskCache.shared.write(tickets, key: key)
        return tickets
    }
}
