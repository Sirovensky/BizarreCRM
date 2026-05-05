import Foundation
import Networking
import Core

// MARK: - NotificationCachedRepository

/// Protocol adding staleness metadata so notification list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol NotificationCachedRepository: Sendable {
    func listNotifications() async throws -> [NotificationItem]
    var lastSyncedAt: Date? { get async }
    func forceRefresh() async throws -> [NotificationItem]
}

// MARK: - NotificationCachedRepositoryImpl

/// In-memory cache wrapper for notification list data.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor NotificationCachedRepositoryImpl: NotificationCachedRepository {

    // MARK: - Properties

    private let api: APIClient
    private let maxAgeSeconds: Int
    private var cachedRows: [NotificationItem] = []
    private var cacheTimestamp: Date?

    // MARK: - Init

    public init(api: APIClient, maxAgeSeconds: Int = 120) {
        self.api = api
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - NotificationCachedRepository

    public var lastSyncedAt: Date? { cacheTimestamp }

    public func listNotifications() async throws -> [NotificationItem] {
        if let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) <= Double(maxAgeSeconds) {
            return cachedRows
        }
        return try await fetchAndCache()
    }

    public func forceRefresh() async throws -> [NotificationItem] {
        try await fetchAndCache()
    }

    // MARK: - Private

    private func fetchAndCache() async throws -> [NotificationItem] {
        let rows = try await api.listNotifications()
        cachedRows = rows
        cacheTimestamp = Date()
        return rows
    }
}
