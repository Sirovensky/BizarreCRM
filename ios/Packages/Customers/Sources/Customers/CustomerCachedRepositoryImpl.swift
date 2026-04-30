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

    /// Pass through to remote — no caching for paginated cursor results.
    public func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage {
        try await remote.listPage(cursor: cursor, query: query)
    }

    public func createFromContact(_ req: ContactImportCreateRequest) async throws {
        try await remote.createFromContact(req)
        cache.removeAll()
    }

    /// Delegates to the underlying repository and invalidates the cache for
    /// all keywords so the next `list(keyword:)` call returns fresh data.
    public func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        let result = try await remote.update(id: id, req)
        cache.removeAll()
        return result
    }

    public func bulkTag(_ req: BulkTagRequest) async throws -> BulkOperationResult {
        let result = try await remote.bulkTag(req)
        cache.removeAll()
        return result
    }

    public func bulkDelete(_ req: BulkDeleteRequest) async throws -> BulkOperationResult {
        let result = try await remote.bulkDelete(req)
        cache.removeAll()
        return result
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
