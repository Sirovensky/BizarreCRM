import Foundation
import Networking
import Core

// MARK: - ExpenseCachedRepository

/// Protocol adding staleness metadata so list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol ExpenseCachedRepository: Sendable {
    func listExpenses(keyword: String?) async throws -> ExpensesListResponse
    var lastSyncedAt: Date? { get async }
    func forceRefresh(keyword: String?) async throws -> ExpensesListResponse
}

// MARK: - ExpenseCachedRepositoryImpl

/// In-memory cache wrapper for expense list data. A separate cache entry is
/// kept per keyword so search results don't evict the unfiltered cache.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor ExpenseCachedRepositoryImpl: ExpenseCachedRepository {

    // MARK: - Types

    private struct CacheEntry {
        let response: ExpensesListResponse
        let timestamp: Date
    }

    // MARK: - Properties

    private let api: APIClient
    private let maxAgeSeconds: Int
    private var cache: [String: CacheEntry] = [:]
    private var globalLastSyncedAt: Date?

    // MARK: - Init

    public init(api: APIClient, maxAgeSeconds: Int = 300) {
        self.api = api
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - ExpenseCachedRepository

    public var lastSyncedAt: Date? { globalLastSyncedAt }

    public func listExpenses(keyword: String?) async throws -> ExpensesListResponse {
        let key = keyword ?? ""
        if let entry = cache[key],
           Date().timeIntervalSince(entry.timestamp) <= Double(maxAgeSeconds) {
            return entry.response
        }
        return try await fetchAndCache(keyword: keyword)
    }

    public func forceRefresh(keyword: String?) async throws -> ExpensesListResponse {
        try await fetchAndCache(keyword: keyword)
    }

    // MARK: - Private

    private func fetchAndCache(keyword: String?) async throws -> ExpensesListResponse {
        let resp = try await api.listExpenses(keyword: keyword)
        let key = keyword ?? ""
        let now = Date()
        cache[key] = CacheEntry(response: resp, timestamp: now)
        globalLastSyncedAt = now
        return resp
    }
}
