import XCTest
@testable import Tickets
import Networking

// MARK: - TicketCachedRepositoryTests

/// Tests for `TicketCachedRepositoryImpl`:
/// - Cache hit avoids a second remote call within maxAge.
/// - Stale cache triggers a remote fetch.
/// - `forceRefresh` always hits remote.
/// - `lastSyncedAt` is populated after a successful fetch.
/// - Remote errors propagate correctly.
/// - Different filter/keyword combos use independent cache entries.

final class TicketCachedRepositoryTests: XCTestCase {

    // MARK: - lastSyncedAt

    func test_lastSyncedAt_isNilBeforeFirstFetch() async {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let ts = await repo.lastSyncedAt
        XCTAssertNil(ts)
    }

    func test_lastSyncedAt_isSetAfterList() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        _ = try await repo.list(filter: .all, keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
    }

    // MARK: - Cache hit

    func test_list_returnsCachedData_withinMaxAge() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(filter: .all, keyword: nil)
        _ = try await repo.list(filter: .all, keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 1, "Remote should only be called once within maxAge window")
    }

    // MARK: - Stale cache

    func test_list_fetchesRemote_whenCacheIsStale() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 0)

        _ = try await repo.list(filter: .all, keyword: nil)
        _ = try await repo.list(filter: .all, keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 2, "Remote should be called each time cache is stale")
    }

    // MARK: - forceRefresh

    func test_forceRefresh_alwaysHitsRemote() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(filter: .all, keyword: nil)  // Populates cache.
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 3)
    }

    func test_forceRefresh_updatesLastSyncedAt() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let before = Date()
        _ = try await repo.forceRefresh(filter: .all, keyword: nil)
        let ts = await repo.lastSyncedAt
        XCTAssertNotNil(ts)
        XCTAssertGreaterThanOrEqual(ts!, before)
    }

    // MARK: - Separate cache keys per filter

    func test_list_usesIndependentCache_perFilter() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(filter: .all, keyword: nil)
        _ = try await repo.list(filter: .open, keyword: nil)

        let count = await remote.callCount
        XCTAssertEqual(count, 2, "Different filters should use independent cache entries")
    }

    func test_list_usesIndependentCache_perKeyword() async throws {
        let remote = SpyTicketRepo()
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        _ = try await repo.list(filter: .all, keyword: "phone")
        _ = try await repo.list(filter: .all, keyword: "laptop")

        let count = await remote.callCount
        XCTAssertEqual(count, 2, "Different keywords should use independent cache entries")
    }

    // MARK: - Error propagation

    func test_list_propagatesRemoteError() async {
        let remote = SpyTicketRepo(shouldFail: true)
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        do {
            _ = try await repo.list(filter: .all, keyword: nil)
            XCTFail("Expected error")
        } catch {
            // Expected.
        }
    }

    // MARK: - Pull-to-refresh round-trip (integration)

    func test_forceRefresh_returnsRemoteData() async throws {
        let remote = SpyTicketRepo(ticketCount: 5)
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)
        let results = try await repo.forceRefresh(filter: .all, keyword: nil)
        XCTAssertEqual(results.count, 5)
    }
}

// MARK: - Performance

final class TicketListPerfTests: XCTestCase {
    /// Baseline: generating 1000 `TicketSummary` values from the cache actor
    /// should complete well within the 1-second XCTest budget.
    ///
    /// NOTE: This test exercises the in-memory read path that backs the `List`
    /// view. A real 60fps benchmark requires an XCUITest; this unit baseline
    /// documents the data-access cost. If this measure exceeds 0.1s on a
    /// baseline run, investigate the cache key hashing or actor hop overhead.
    func test_cachedList_1000Rows_performance() throws {
        let remote = SpyTicketRepo(ticketCount: 1_000)
        let repo = TicketCachedRepositoryImpl(remote: remote, maxAgeSeconds: 300)

        // Warm the cache synchronously via a detached task.
        let warmExp = self.expectation(description: "cache warm")
        Task {
            _ = try? await repo.list(filter: .all, keyword: nil)
            warmExp.fulfill()
        }
        wait(for: [warmExp], timeout: 5)

        measure {
            // Read from warmed cache — no remote call, pure in-memory access.
            let readExp = self.expectation(description: "measure read")
            Task {
                _ = try? await repo.list(filter: .all, keyword: nil)
                readExp.fulfill()
            }
            self.wait(for: [readExp], timeout: 5)
        }
    }
}

// MARK: - Helpers

private actor SpyTicketRepo: TicketRepository {
    private let shouldFail: Bool
    private let ticketCount: Int
    private(set) var callCount: Int = 0

    init(shouldFail: Bool = false, ticketCount: Int = 0) {
        self.shouldFail = shouldFail
        self.ticketCount = ticketCount
    }

    func list(filter: TicketListFilter, keyword: String?, sort: TicketSortOrder) async throws -> [TicketSummary] {
        callCount += 1
        if shouldFail { throw RepoTestError.boom }
        return (0..<ticketCount).map { makeTicket(index: $0) }
    }

    func detail(id: Int64) async throws -> TicketDetail {
        throw RepoTestError.boom
    }

    func delete(id: Int64) async throws { throw RepoTestError.boom }
    func duplicate(id: Int64) async throws -> DuplicateTicketResponse { throw RepoTestError.boom }
    func convertToInvoice(id: Int64) async throws -> ConvertToInvoiceResponse { throw RepoTestError.boom }

    private func makeTicket(index: Int) -> TicketSummary {
        // TicketSummary has explicit CodingKeys that map snake_case JSON keys.
        // Do NOT use convertFromSnakeCase — keys are already explicit.
        let json = """
        {
          "id": \(index),
          "order_id": "T-\(index)",
          "total": 1000,
          "is_pinned": false,
          "created_at": "2025-01-01T00:00:00Z",
          "updated_at": "2025-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(TicketSummary.self, from: json)
    }
}

private enum RepoTestError: Error { case boom }
