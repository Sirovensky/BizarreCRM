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
    /// BUGHUNT-2026-05-17: single-flight inflight tracker. Two concurrent
    /// cache-miss callers used to spawn separate listSmsConversations calls —
    /// the `await` inside `fetchAndCache` releases the actor so the second
    /// caller observed an empty cache and fired its own request.
    private var inflight: [String: Task<[SmsConversation], Error>] = [:]

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

    public func markRead(phone: String) async throws {
        try await api.markSmsThreadRead(phone: phone)
        // Invalidate cache so unread count refreshes on next list load.
        cache.removeAll()
    }

    public func toggleFlag(phone: String) async throws -> Bool {
        let result = try await api.toggleSmsConversationFlag(phone: phone)
        // Invalidate cached list so flag badge updates.
        cache.removeAll()
        return result.isFlagged
    }

    public func togglePin(phone: String) async throws -> Bool {
        let result = try await api.toggleSmsConversationPin(phone: phone)
        // Invalidate cached list so pin icon and sort order update.
        cache.removeAll()
        return result.isPinned
    }

    public func toggleArchive(phone: String) async throws -> Bool {
        let result = try await api.toggleSmsConversationArchive(phone: phone)
        // Invalidate cached list so archived conversations are filtered correctly.
        cache.removeAll()
        return result.isArchived
    }

    // MARK: - SmsCachedRepository

    public var lastSyncedAt: Date? { globalLastSyncedAt }

    public func forceRefresh(keyword: String?) async throws -> [SmsConversation] {
        try await fetchAndCache(keyword: keyword)
    }

    // MARK: - Private

    private func fetchAndCache(keyword: String?) async throws -> [SmsConversation] {
        let key = keyword ?? ""
        if let existing = inflight[key] {
            return try await existing.value
        }
        let task = Task<[SmsConversation], Error> { [keyword, key] in
            try await self.performFetch(keyword: keyword, key: key)
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }

    /// Actor-isolated network call + cache write. Factored out so the Task in
    /// `fetchAndCache` can be a `@Sendable` closure that hops onto the actor.
    private func performFetch(keyword: String?, key: String) async throws -> [SmsConversation] {
        let rows = try await api.listSmsConversations(keyword: keyword)
        let now = Date()
        cache[key] = CacheEntry(rows: rows, timestamp: now)
        globalLastSyncedAt = now
        return rows
    }
}
