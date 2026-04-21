import Foundation
import Networking
import Core

// MARK: - SmsCachedRepository

/// Protocol adding staleness metadata so SMS list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol SmsCachedRepository: SmsRepository {
    var lastSyncedAt: Date? { get async }
    func forceRefresh(keyword: String?) async throws -> [SmsConversation]
}

// MARK: - SmsCachedRepositoryImpl

/// In-memory cache wrapper for SMS conversation list data. A separate entry
/// is kept per keyword so search results don't evict the unfiltered cache.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor SmsCachedRepositoryImpl: SmsCachedRepository {

    // MARK: - Types

    private struct CacheEntry {
        let rows: [SmsConversation]
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

    // MARK: - SmsRepository

    public func listConversations(keyword: String?) async throws -> [SmsConversation] {
        let key = keyword ?? ""
        if let entry = cache[key],
           Date().timeIntervalSince(entry.timestamp) <= Double(maxAgeSeconds) {
            return entry.rows
        }
        return try await fetchAndCache(keyword: keyword)
    }

    // MARK: - SmsCachedRepository

    public var lastSyncedAt: Date? { globalLastSyncedAt }

    public func forceRefresh(keyword: String?) async throws -> [SmsConversation] {
        try await fetchAndCache(keyword: keyword)
    }

    // MARK: - Private

    private func fetchAndCache(keyword: String?) async throws -> [SmsConversation] {
        let rows = try await api.listSmsConversations(keyword: keyword)
        let key = keyword ?? ""
        let now = Date()
        cache[key] = CacheEntry(rows: rows, timestamp: now)
        globalLastSyncedAt = now
        return rows
    }
}
