import Foundation
import Networking
import Core

// MARK: - LeadCachedRepository

/// Protocol extending `SmsRepository` with staleness metadata so list views
/// can show a `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol LeadCachedRepository: Sendable {
    func listLeads(keyword: String?) async throws -> [Lead]
    var lastSyncedAt: Date? { get async }
    func forceRefresh(keyword: String?) async throws -> [Lead]
}

// MARK: - LeadCachedRepositoryImpl

/// In-memory cache wrapper for lead list data. Stores the last-fetched slice
/// per keyword (nil keyword = "all"). A separate cache entry is kept per
/// keyword so search results don't evict the unfiltered cache.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor LeadCachedRepositoryImpl: LeadCachedRepository {

    // MARK: - Types

    private struct CacheEntry {
        let rows: [Lead]
        let timestamp: Date
    }

    // MARK: - Properties

    private let api: APIClient
    private let maxAgeSeconds: Int
    private var cache: [String: CacheEntry] = [:]
    /// Most-recent successful fetch across all keywords (used for StalenessIndicator).
    private var globalLastSyncedAt: Date?

    // MARK: - Init

    public init(api: APIClient, maxAgeSeconds: Int = 300) {
        self.api = api
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - LeadCachedRepository

    public var lastSyncedAt: Date? { globalLastSyncedAt }

    public func listLeads(keyword: String?) async throws -> [Lead] {
        let key = keyword ?? ""
        if let entry = cache[key],
           Date().timeIntervalSince(entry.timestamp) <= Double(maxAgeSeconds) {
            return entry.rows
        }
        return try await fetchAndCache(keyword: keyword)
    }

    public func forceRefresh(keyword: String?) async throws -> [Lead] {
        try await fetchAndCache(keyword: keyword)
    }

    // MARK: - Private

    private func fetchAndCache(keyword: String?) async throws -> [Lead] {
        let rows = try await api.listLeads(keyword: keyword)
        let key = keyword ?? ""
        let now = Date()
        cache[key] = CacheEntry(rows: rows, timestamp: now)
        globalLastSyncedAt = now
        return rows
    }
}
