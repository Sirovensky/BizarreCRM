import Foundation
import Networking
import Core

// MARK: - AppointmentCachedRepository

/// Protocol adding staleness metadata so list views can show a
/// `StalenessIndicator` chip and force-refresh on pull-to-refresh.
public protocol AppointmentCachedRepository: Sendable {
    func listAppointments() async throws -> [Appointment]
    var lastSyncedAt: Date? { get async }
    func forceRefresh() async throws -> [Appointment]
}

// MARK: - AppointmentCachedRepositoryImpl

/// In-memory cache wrapper for appointment list data.
///
/// TODO(phase-4): Persist cache to GRDB so cold launches get instant data.
/// TODO(phase-10): XCTest perf benchmark — 1000 rows × 60fps. See §29 perf budget.
public actor AppointmentCachedRepositoryImpl: AppointmentCachedRepository {

    // MARK: - Properties

    private let api: APIClient
    private let maxAgeSeconds: Int
    private var cachedRows: [Appointment] = []
    private var cacheTimestamp: Date?

    // MARK: - Init

    public init(api: APIClient, maxAgeSeconds: Int = 300) {
        self.api = api
        self.maxAgeSeconds = maxAgeSeconds
    }

    // MARK: - AppointmentCachedRepository

    public var lastSyncedAt: Date? { cacheTimestamp }

    public func listAppointments() async throws -> [Appointment] {
        if let ts = cacheTimestamp,
           Date().timeIntervalSince(ts) <= Double(maxAgeSeconds) {
            return cachedRows
        }
        return try await fetchAndCache()
    }

    public func forceRefresh() async throws -> [Appointment] {
        try await fetchAndCache()
    }

    // MARK: - Private

    private func fetchAndCache() async throws -> [Appointment] {
        let rows = try await api.listAppointments()
        cachedRows = rows
        cacheTimestamp = Date()
        return rows
    }
}
