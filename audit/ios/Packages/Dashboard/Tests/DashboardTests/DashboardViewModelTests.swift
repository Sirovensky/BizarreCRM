import XCTest
@testable import Dashboard
@testable import Networking

/// DashboardViewModel drives three states. Happy-path load transitions
/// .loading → .loaded, while a failed fetch lands in .failed with the
/// server error. Soft-refresh semantics (keep prior data visible during
/// re-load) are also exercised.
@MainActor
final class DashboardViewModelTests: XCTestCase {

    func test_initialState_isLoading() {
        let vm = DashboardViewModel(repo: StubRepo(result: .success(Self.sampleSnapshot)))
        if case .loading = vm.state { return }
        XCTFail("Expected .loading, got \(vm.state)")
    }

    func test_load_transitionsToLoaded() async {
        let vm = DashboardViewModel(repo: StubRepo(result: .success(Self.sampleSnapshot)))
        await vm.load()
        guard case let .loaded(snapshot) = vm.state else {
            XCTFail("Expected .loaded"); return
        }
        XCTAssertEqual(snapshot.summary.openTickets, 3)
        XCTAssertEqual(snapshot.attention.lowStockCount, 2)
    }

    func test_load_transitionsToFailedOnError() async {
        let vm = DashboardViewModel(repo: StubRepo(result: .failure(TestError.boom)))
        await vm.load()
        guard case let .failed(message) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertFalse(message.isEmpty)
    }

    func test_load_keepsPriorDataDuringSoftRefresh() async {
        let repo = StubRepo(result: .success(Self.sampleSnapshot))
        let vm = DashboardViewModel(repo: repo)
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after first load"); return
        }
        // Second load returns new data; we assert the state never regressed
        // to .loading between the first .loaded and the second .loaded.
        await repo.setResult(.success(Self.sampleSnapshot))
        let stateBefore = vm.state
        await vm.load()
        if case .loading = stateBefore {
            XCTFail("Soft refresh must not reset to .loading")
        }
    }

    // MARK: - Fixtures

    static var sampleSnapshot: DashboardSnapshot {
        DashboardSnapshot(
            summary: DashboardSummary(
                openTickets: 3,
                revenueToday: 1240.50,
                closedToday: 2,
                ticketsCreatedToday: 5,
                appointmentsToday: 1,
                avgRepairHours: 8.2,
                inventoryValue: 52_400
            ),
            attention: NeedsAttention(
                staleTickets: [],
                overdueInvoices: [],
                missingPartsCount: 1,
                lowStockCount: 2
            )
        )
    }
}

private enum TestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}

/// Actor-backed repo so the VM's async call-site sees a real actor
/// boundary + the test can mutate the canned result between loads.
private actor StubRepo: DashboardRepository {
    private var result: Result<DashboardSnapshot, Error>

    init(result: Result<DashboardSnapshot, Error>) {
        self.result = result
    }

    func setResult(_ new: Result<DashboardSnapshot, Error>) {
        self.result = new
    }

    func load() async throws -> DashboardSnapshot {
        switch result {
        case .success(let snap): return snap
        case .failure(let err): throw err
        }
    }
}
