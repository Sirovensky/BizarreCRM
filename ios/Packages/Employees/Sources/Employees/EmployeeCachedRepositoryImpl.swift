import Foundation
import Networking
import Core

// MARK: - EmployeeCachedRepository

/// Protocol adding staleness metadata so employee list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol EmployeeCachedRepository: Sendable {
    func listEmployees() async throws -> [Employee]
    var lastSyncedAt: Date? { get async }
    func forceRefresh() async throws -> [Employee]
}

// MARK: - EmployeeCachedRepositoryImpl

/// In-memory cache wrapper for employee list data.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor EmployeeCachedRepositoryImpl: EmployeeCachedRepository {

    // MARK: - Properties

    private let api: APIClient
    private let maxAgeSeconds: Int
    private var cachedRows: [Employee] = []
    private var cacheTimestamp: Date?

    // MARK: - Init

    public init(api: APIClient, maxAgeSeconds: Int = 300) {
        self.api = api
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - EmployeeCachedRepository

    public var lastSyncedAt: Date? { cacheTimestamp }

    public func listEmployees() async throws -> [Employee] {
        if let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) <= Double(maxAgeSeconds) {
            return cachedRows
        }
        return try await fetchAndCache()
    }

    public func forceRefresh() async throws -> [Employee] {
        try await fetchAndCache()
    }

    // MARK: - Private

    private func fetchAndCache() async throws -> [Employee] {
        let rows = try await api.listEmployees()
        cachedRows = rows
        cacheTimestamp = Date()
        return rows
    }
}
