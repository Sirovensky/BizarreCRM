import Foundation
import Networking
import Core

// MARK: - ExpenseListFilter

/// Filter parameters forwarded to `GET /expenses` query string.
/// All fields are optional; nil/empty values are omitted from the request.
public struct ExpenseListFilter: Sendable, Equatable {
    public var category: String?
    public var fromDate: String?
    public var toDate: String?
    public var status: String?

    public init(
        category: String? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        status: String? = nil
    ) {
        self.category = category
        self.fromDate = fromDate
        self.toDate = toDate
        self.status = status
    }

    public var isEmpty: Bool {
        (category?.isEmpty ?? true)
            && (fromDate?.isEmpty ?? true)
            && (toDate?.isEmpty ?? true)
            && (status?.isEmpty ?? true)
    }
}

// MARK: - ExpenseCachedRepository

/// Protocol adding staleness metadata so list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol ExpenseCachedRepository: Sendable {
    func listExpenses(keyword: String?, filter: ExpenseListFilter) async throws -> ExpensesListResponse
    var lastSyncedAt: Date? { get async }
    func forceRefresh(keyword: String?, filter: ExpenseListFilter) async throws -> ExpensesListResponse
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

    public func listExpenses(keyword: String?, filter: ExpenseListFilter = .init()) async throws -> ExpensesListResponse {
        let key = cacheKey(keyword: keyword, filter: filter)
        if let entry = cache[key],
           Date().timeIntervalSince(entry.timestamp) <= Double(maxAgeSeconds) {
            return entry.response
        }
        return try await fetchAndCache(keyword: keyword, filter: filter)
    }

    public func forceRefresh(keyword: String?, filter: ExpenseListFilter = .init()) async throws -> ExpensesListResponse {
        try await fetchAndCache(keyword: keyword, filter: filter)
    }

    // MARK: - Private

    private func cacheKey(keyword: String?, filter: ExpenseListFilter) -> String {
        "\(keyword ?? "")|\(filter.category ?? "")|\(filter.fromDate ?? "")|\(filter.toDate ?? "")|\(filter.status ?? "")"
    }

    private func fetchAndCache(keyword: String?, filter: ExpenseListFilter) async throws -> ExpensesListResponse {
        let resp = try await api.listExpenses(
            keyword: keyword,
            category: filter.category.flatMap { $0.isEmpty ? nil : $0 },
            fromDate: filter.fromDate.flatMap { $0.isEmpty ? nil : $0 },
            toDate: filter.toDate.flatMap { $0.isEmpty ? nil : $0 },
            status: filter.status.flatMap { $0.isEmpty ? nil : $0 }
        )
        let key = cacheKey(keyword: keyword, filter: filter)
        let now = Date()
        cache[key] = CacheEntry(response: resp, timestamp: now)
        globalLastSyncedAt = now
        return resp
    }
}
