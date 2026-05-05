import XCTest
@testable import Dashboard
import Networking

// MARK: - DashboardViewModelCachedTests

/// Tests exercising cached-repo integration in `DashboardViewModel`:
/// - `lastSyncedAt` is updated after load/forceRefresh.
/// - `forceRefresh()` calls `forceRefresh()` on the cached repo.
/// - Non-cached repos fall back to `load()`.

@MainActor
final class DashboardViewModelCachedTests: XCTestCase {

    static var sampleSnapshot: DashboardSnapshot {
        DashboardSnapshot(
            summary: DashboardSummary(
                openTickets: 1,
                revenueToday: 100,
                closedToday: 0,
                ticketsCreatedToday: 1,
                appointmentsToday: 0,
                avgRepairHours: 2,
                inventoryValue: 500
            ),
            attention: NeedsAttention(
                staleTickets: [],
                overdueInvoices: [],
                missingPartsCount: 0,
                lowStockCount: 0
            )
        )
    }

    // MARK: - lastSyncedAt via cached repo

    func test_lastSyncedAt_isNilInitially() {
        let repo = StubCachedRepo(snapshot: Self.sampleSnapshot)
        let vm = DashboardViewModel(repo: repo)
        XCTAssertNil(vm.lastSyncedAt)
    }

    func test_lastSyncedAt_isSetAfterLoad() async {
        let repo = StubCachedRepo(snapshot: Self.sampleSnapshot)
        let vm = DashboardViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.lastSyncedAt)
    }

    // MARK: - forceRefresh dispatches to cached repo

    func test_forceRefresh_callsForceRefreshOnCachedRepo() async {
        let repo = StubCachedRepo(snapshot: Self.sampleSnapshot)
        let vm = DashboardViewModel(repo: repo)
        await vm.forceRefresh()
        let count = await repo.forceRefreshCount
        XCTAssertEqual(count, 1)
    }

    func test_forceRefresh_updatesLastSyncedAt() async {
        let repo = StubCachedRepo(snapshot: Self.sampleSnapshot)
        let vm = DashboardViewModel(repo: repo)
        let before = Date()
        await vm.forceRefresh()
        XCTAssertNotNil(vm.lastSyncedAt)
        XCTAssertGreaterThanOrEqual(vm.lastSyncedAt!, before)
    }

    func test_forceRefresh_setsLoadedState() async {
        let repo = StubCachedRepo(snapshot: Self.sampleSnapshot)
        let vm = DashboardViewModel(repo: repo)
        await vm.forceRefresh()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after forceRefresh")
            return
        }
    }

    func test_forceRefresh_propagatesError_toFailedState() async {
        let repo = StubCachedRepo(shouldFail: true)
        let vm = DashboardViewModel(repo: repo)
        await vm.forceRefresh()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed when forceRefresh throws")
            return
        }
    }

    // MARK: - Non-cached repo falls back to load()

    func test_forceRefresh_withNonCachedRepo_callsLoad() async {
        let repo = PlainStubRepo(result: .success(Self.sampleSnapshot))
        let vm = DashboardViewModel(repo: repo)
        await vm.forceRefresh()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded via fallback load()")
            return
        }
    }
}

// MARK: - Stubs

private actor StubCachedRepo: DashboardCachedRepository {
    private let snapshot: DashboardSnapshot?
    private let shouldFail: Bool
    private(set) var forceRefreshCount: Int = 0
    private var syncedAt: Date?

    init(snapshot: DashboardSnapshot? = nil, shouldFail: Bool = false) {
        self.snapshot = snapshot
        self.shouldFail = shouldFail
    }

    var lastSyncedAt: Date? { syncedAt }

    func load() async throws -> DashboardSnapshot {
        guard !shouldFail, let snap = snapshot else { throw VMTestError.boom }
        syncedAt = Date()
        return snap
    }

    func forceRefresh() async throws -> DashboardSnapshot {
        forceRefreshCount += 1
        guard !shouldFail, let snap = snapshot else { throw VMTestError.boom }
        syncedAt = Date()
        return snap
    }
}

private actor PlainStubRepo: DashboardRepository {
    private let result: Result<DashboardSnapshot, Error>

    init(result: Result<DashboardSnapshot, Error>) {
        self.result = result
    }

    func load() async throws -> DashboardSnapshot {
        switch result {
        case .success(let snap): return snap
        case .failure(let err): throw err
        }
    }
}

private enum VMTestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}
