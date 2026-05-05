import XCTest
@testable import Dashboard
@testable import Networking

// MARK: - DashboardCachedRepositoryTests

/// Tests for `DashboardCachedRepositoryImpl`:
/// - Cache hit avoids a second remote call.
/// - Stale cache (age > maxAge) triggers a remote fetch.
/// - `forceRefresh()` always hits remote regardless of cache age.
/// - `lastSyncedAt` is populated after a successful fetch.
/// - Remote errors propagate correctly.

final class DashboardCachedRepositoryTests: XCTestCase {

    // MARK: - Fixtures

    static var sampleSnapshot: DashboardSnapshot {
        DashboardSnapshot(
            summary: DashboardSummary(
                openTickets: 5,
                revenueToday: 999.0,
                closedToday: 1,
                ticketsCreatedToday: 3,
                appointmentsToday: 2,
                avgRepairHours: 4.0,
                inventoryValue: 10_000
            ),
            attention: NeedsAttention(
                staleTickets: [],
                overdueInvoices: [],
                missingPartsCount: 0,
                lowStockCount: 0
            )
        )
    }

    // MARK: - lastSyncedAt

    func test_lastSyncedAt_isNilBeforeFirstFetch() async {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_isSetAfterLoad() async throws {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        _ = try await repo.load()
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
    }

    // MARK: - Cache hit

    func test_load_returnsCachedData_withinMaxAge() async throws {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.load()  // First fetch — calls remote.
        _ = try await repo.load()  // Second fetch — should be cache hit.

        let callCount = await remote.callCount
        XCTAssertEqual(callCount, 1, "Remote should only be called once within maxAge window")
    }

    // MARK: - Stale cache

    func test_load_fetchesRemote_whenCacheIsStale() async throws {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        // maxAgeSeconds = 0 → always stale after first fetch
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 0)

        _ = try await repo.load()
        _ = try await repo.load()

        let callCount = await remote.callCount
        XCTAssertEqual(callCount, 2, "Remote should be called on each stale load")
    }

    // MARK: - forceRefresh

    func test_forceRefresh_alwaysHitsRemote() async throws {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.load()        // Cache populated.
        _ = try await repo.forceRefresh() // Must bypass cache.
        _ = try await repo.forceRefresh() // Must bypass cache again.

        let callCount = await remote.callCount
        XCTAssertEqual(callCount, 3)
    }

    func test_forceRefresh_updatesLastSyncedAt() async throws {
        let remote = SpyRepo(result: .success(Self.sampleSnapshot))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        let before = Date()
        _ = try await repo.forceRefresh()
        let ts = await repo.lastSyncedAt

        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(ts!, before)
    }

    // MARK: - Error propagation

    func test_load_propagatesRemoteError() async {
        let remote = SpyRepo(result: .failure(TestError.boom))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        do {
            _ = try await repo.load()
            XCTFail("Expected error to be thrown")
        } catch {
            // Success — error propagated correctly.
        }
    }

    func test_forceRefresh_propagatesRemoteError() async {
        let remote = SpyRepo(result: .failure(TestError.boom))
        let repo = DashboardCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        do {
            _ = try await repo.forceRefresh()
            XCTFail("Expected error to be thrown")
        } catch {
            // Success — error propagated correctly.
        }
    }
}

// MARK: - Helpers

private enum TestError: Error { case boom }

private actor SpyRepo: DashboardRepository {
    private let result: Result<DashboardSnapshot, Error>
    private(set) var callCount: Int = 0

    init(result: Result<DashboardSnapshot, Error>) {
        self.result = result
    }

    func load() async throws -> DashboardSnapshot {
        callCount += 1
        switch result {
        case .success(let snap): return snap
        case .failure(let err): throw err
        }
    }
}
