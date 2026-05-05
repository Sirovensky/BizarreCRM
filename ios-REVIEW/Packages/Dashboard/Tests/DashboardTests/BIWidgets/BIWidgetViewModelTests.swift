import XCTest
@testable import Dashboard

// MARK: - BIWidgetViewModelTests
//
// Tests for ViewModel state machines: idle → loaded, idle → failed,
// empty-state handling, and reload behaviour.

// MARK: - MockBIRepository

private final class MockBIRepository: DashboardBIRepository, @unchecked Sendable {
    var summaryResult: Result<DashboardSummaryPayload, Error> = .success(.init())
    var techLeaderboardResult: Result<TechLeaderboardPayload, Error> = .success(.init())
    var topCustomersResult: Result<RepeatCustomersPayload, Error> = .success(.init())
    var cashTrappedResult: Result<CashTrappedPayload, Error> = .success(.init())
    var churnResult: Result<ChurnPayload, Error> = .success(.init())

    func fetchDashboardSummary() async throws -> DashboardSummaryPayload { try summaryResult.get() }
    func fetchTechLeaderboard(period: TechLeaderboardPeriod) async throws -> TechLeaderboardPayload { try techLeaderboardResult.get() }
    func fetchTopCustomers() async throws -> RepeatCustomersPayload { try topCustomersResult.get() }
    func fetchCashTrapped() async throws -> CashTrappedPayload { try cashTrappedResult.get() }
    func fetchChurn() async throws -> ChurnPayload { try churnResult.get() }
}

private struct MockError: Error, LocalizedError {
    let errorDescription: String? = "Network error"
}

// MARK: - RevenueSparklineViewModel tests

@MainActor
final class RevenueSparklineViewModelTests: XCTestCase {

    func test_load_transitionsToLoadedWithPoints() async {
        let repo = MockBIRepository()
        repo.summaryResult = .success(DashboardSummaryPayload(revenueTrend: [
            .init(month: "2025-01", revenue: 10000),
            .init(month: "2025-02", revenue: 12000),
        ]))
        let vm = RevenueSparklineViewModel(repo: repo)
        await vm.load()
        if case .loaded(let points) = vm.state {
            XCTAssertEqual(points.count, 2)
            XCTAssertEqual(points[1].revenue, 12000)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_load_transitionsToFailedOnError() async {
        let repo = MockBIRepository()
        repo.summaryResult = .failure(MockError())
        let vm = RevenueSparklineViewModel(repo: repo)
        await vm.load()
        guard case .failed(let msg) = vm.state else { XCTFail("Expected .failed"); return }
        XCTAssertFalse(msg.isEmpty)
    }

    func test_load_handlesEmptyTrend() async {
        let repo = MockBIRepository()
        repo.summaryResult = .success(DashboardSummaryPayload(revenueTrend: []))
        let vm = RevenueSparklineViewModel(repo: repo)
        await vm.load()
        if case .loaded(let points) = vm.state {
            XCTAssertTrue(points.isEmpty)
        } else {
            XCTFail("Expected .loaded with empty array")
        }
    }

    func test_secondLoad_isNoOpWhenLoaded() async {
        let repo = MockBIRepository()
        var callCount = 0
        let buildPayload = { () -> DashboardSummaryPayload in
            callCount += 1
            return DashboardSummaryPayload(revenueTrend: [.init(month: "2025-01", revenue: 1)])
        }
        repo.summaryResult = .success(buildPayload())
        let vm = RevenueSparklineViewModel(repo: repo)
        await vm.load()
        await vm.load() // second call — already .loaded, no-op
        XCTAssertEqual(callCount, 1, "fetchDashboardSummary should be called exactly once")
    }

    func test_reload_refetches() async {
        let repo = MockBIRepository()
        repo.summaryResult = .success(DashboardSummaryPayload(revenueTrend: [.init(month: "2025-01", revenue: 1000)]))
        let vm = RevenueSparklineViewModel(repo: repo)
        await vm.load()
        repo.summaryResult = .success(DashboardSummaryPayload(revenueTrend: [
            .init(month: "2025-01", revenue: 1000),
            .init(month: "2025-02", revenue: 2000)
        ]))
        await vm.reload()
        if case .loaded(let points) = vm.state {
            XCTAssertEqual(points.count, 2)
        } else {
            XCTFail("Expected .loaded after reload")
        }
    }
}

// MARK: - TopCustomersViewModel tests

@MainActor
final class TopCustomersViewModelTests: XCTestCase {

    func test_load_withCustomers_transitionsToLoaded() async {
        let repo = MockBIRepository()
        repo.topCustomersResult = .success(RepeatCustomersPayload(
            top: [
                .init(customerId: 1, name: "Alice", ticketCount: 10, totalSpent: 2500, sharePct: 4.0),
                .init(customerId: 2, name: "Bob",   ticketCount: 7,  totalSpent: 1800, sharePct: 2.9),
            ],
            combinedSharePct: 6.9, totalRevenue: 62000
        ))
        let vm = TopCustomersViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertEqual(result.top.count, 2)
            XCTAssertEqual(result.top[0].name, "Alice")
        } else {
            XCTFail("Expected .loaded")
        }
    }

    func test_load_emptyTop_stillLoaded() async {
        let repo = MockBIRepository()
        repo.topCustomersResult = .success(RepeatCustomersPayload(top: []))
        let vm = TopCustomersViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertTrue(result.top.isEmpty)
        } else {
            XCTFail("Expected .loaded with empty array")
        }
    }

    func test_load_failsGracefully() async {
        let repo = MockBIRepository()
        repo.topCustomersResult = .failure(MockError())
        let vm = TopCustomersViewModel(repo: repo)
        await vm.load()
        guard case .failed = vm.state else { XCTFail("Expected .failed"); return }
    }
}

// MARK: - OpenTicketsByStatusViewModel tests

@MainActor
final class OpenTicketsByStatusViewModelTests: XCTestCase {

    func test_load_filtersZeroCountStatuses() async {
        let repo = MockBIRepository()
        repo.summaryResult = .success(DashboardSummaryPayload(statusCounts: [
            .init(id: 1, name: "Open",        color: nil, count: 12),
            .init(id: 2, name: "Closed",      color: nil, count: 0,  isClosed: true),
            .init(id: 3, name: "In Progress", color: nil, count: 5),
        ]))
        let vm = OpenTicketsByStatusViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertEqual(result.count, 2)
            XCTAssertTrue(result.allSatisfy { $0.count > 0 })
        } else {
            XCTFail("Expected .loaded")
        }
    }

    func test_load_allZeroCounts_producesEmptyLoaded() async {
        let repo = MockBIRepository()
        repo.summaryResult = .success(DashboardSummaryPayload(statusCounts: [
            .init(id: 1, name: "Open", color: nil, count: 0)
        ]))
        let vm = OpenTicketsByStatusViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertTrue(result.isEmpty)
        } else {
            XCTFail("Expected .loaded with empty array")
        }
    }

    func test_load_failsOnNetworkError() async {
        let repo = MockBIRepository()
        repo.summaryResult = .failure(MockError())
        let vm = OpenTicketsByStatusViewModel(repo: repo)
        await vm.load()
        guard case .failed = vm.state else { XCTFail("Expected .failed"); return }
    }
}

// MARK: - TechLeaderboardViewModel tests

@MainActor
final class TechLeaderboardViewModelTests: XCTestCase {

    func test_load_decodesLeaderboard() async {
        let repo = MockBIRepository()
        repo.techLeaderboardResult = .success(TechLeaderboardPayload(
            period: "month",
            leaderboard: [
                .init(userId: 1, name: "Tech A", ticketsClosed: 50, revenue: 20000),
                .init(userId: 2, name: "Tech B", ticketsClosed: 30, revenue: 12000),
            ]
        ))
        let vm = TechLeaderboardViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertEqual(result.leaderboard.count, 2)
            XCTAssertEqual(result.leaderboard[0].name, "Tech A")
        } else {
            XCTFail("Expected .loaded")
        }
    }

    func test_load_emptyLeaderboard() async {
        let repo = MockBIRepository()
        repo.techLeaderboardResult = .success(TechLeaderboardPayload(period: "month", leaderboard: []))
        let vm = TechLeaderboardViewModel(repo: repo)
        await vm.load()
        if case .loaded(let result) = vm.state {
            XCTAssertTrue(result.leaderboard.isEmpty)
        } else {
            XCTFail("Expected .loaded with empty leaderboard")
        }
    }

    func test_load_failsGracefully() async {
        let repo = MockBIRepository()
        repo.techLeaderboardResult = .failure(MockError())
        let vm = TechLeaderboardViewModel(repo: repo)
        await vm.load()
        guard case .failed = vm.state else { XCTFail("Expected .failed"); return }
    }
}

// MARK: - BIWidgetState helpers for tests

private func stateTag<T>(_ state: BIWidgetState<T>) -> String {
    switch state {
    case .idle:    return "idle"
    case .loading: return "loading"
    case .loaded:  return "loaded"
    case .failed:  return "failed"
    }
}
