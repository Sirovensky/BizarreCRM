import XCTest
@testable import Tickets
import Networking

// MARK: - TicketListViewModelCachedTests

/// Tests exercising `TicketListViewModel` with a cached repository:
/// - `refresh()` calls `forceRefresh()` on the cached repo (pull-to-refresh round-trip).
/// - `lastSyncedAt` is updated after load and refresh.
/// - `refresh()` with a non-cached repo falls back to `fetch()`.

@MainActor
final class TicketListViewModelCachedTests: XCTestCase {

    // MARK: - lastSyncedAt

    func test_lastSyncedAt_isNilInitially() {
        let repo = StubCachedTicketRepo()
        let vm = TicketListViewModel(repo: repo)
        XCTAssertNil(vm.lastSyncedAt)
    }

    func test_lastSyncedAt_isSetAfterLoad() async {
        let repo = StubCachedTicketRepo()
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.lastSyncedAt)
    }

    // MARK: - Pull-to-refresh round-trip

    func test_refresh_callsForceRefreshOnCachedRepo() async {
        let repo = StubCachedTicketRepo()
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        await vm.refresh()
        let count = await repo.forceRefreshCount
        XCTAssertEqual(count, 1, "pull-to-refresh must call forceRefresh() on the cached repo")
    }

    func test_refresh_updatesLastSyncedAt() async {
        let repo = StubCachedTicketRepo()
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        let before = Date()
        await vm.refresh()
        XCTAssertNotNil(vm.lastSyncedAt)
        XCTAssertGreaterThanOrEqual(vm.lastSyncedAt!, before)
    }

    func test_refresh_updatesTickets() async {
        let repo = StubCachedTicketRepo(ticketCount: 3)
        let vm = TicketListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.tickets.count, 3)

        await repo.setTicketCount(10)
        await vm.refresh()
        XCTAssertEqual(vm.tickets.count, 10)
    }

    func test_refresh_setsErrorMessage_onFailure() async {
        let repo = StubCachedTicketRepo(shouldFail: true)
        let vm = TicketListViewModel(repo: repo)
        await vm.refresh()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Non-cached fallback

    func test_refresh_withNonCachedRepo_fallsBackToFetch() async {
        let repo = PlainStubTicketRepo(ticketCount: 4)
        let vm = TicketListViewModel(repo: repo)
        await vm.refresh()
        XCTAssertEqual(vm.tickets.count, 4)
    }
}

// MARK: - Stubs

private actor StubCachedTicketRepo: TicketCachedRepository {
    private var ticketCount: Int
    private var shouldFail: Bool
    private(set) var forceRefreshCount: Int = 0
    private var syncedAt: Date?

    init(ticketCount: Int = 2, shouldFail: Bool = false) {
        self.ticketCount = ticketCount
        self.shouldFail = shouldFail
    }

    func setTicketCount(_ count: Int) {
        ticketCount = count
    }

    var lastSyncedAt: Date? { syncedAt }

    func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        if shouldFail { throw TVMTestError.boom }
        syncedAt = Date()
        return makeTickets(count: ticketCount)
    }

    func forceRefresh(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        forceRefreshCount += 1
        if shouldFail { throw TVMTestError.boom }
        syncedAt = Date()
        return makeTickets(count: ticketCount)
    }

    func detail(id: Int64) async throws -> TicketDetail {
        throw TVMTestError.boom
    }

    private func makeTickets(count: Int) -> [TicketSummary] {
        (0..<count).map { index in
            let json = """
            {
              "id": \(index),
              "order_id": "T-\(index)",
              "total": 0,
              "is_pinned": false,
              "created_at": "2025-01-01T00:00:00Z",
              "updated_at": "2025-01-01T00:00:00Z"
            }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(TicketSummary.self, from: json)
        }
    }
}

private actor PlainStubTicketRepo: TicketRepository {
    private let ticketCount: Int

    init(ticketCount: Int) {
        self.ticketCount = ticketCount
    }

    func list(filter: TicketListFilter, keyword: String?) async throws -> [TicketSummary] {
        (0..<ticketCount).map { index in
            let json = """
            {
              "id": \(index),
              "order_id": "T-\(index)",
              "total": 0,
              "is_pinned": false,
              "created_at": "2025-01-01T00:00:00Z",
              "updated_at": "2025-01-01T00:00:00Z"
            }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(TicketSummary.self, from: json)
        }
    }

    func detail(id: Int64) async throws -> TicketDetail {
        throw TVMTestError.boom
    }
}

private enum TVMTestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}
