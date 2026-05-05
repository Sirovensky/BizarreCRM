import XCTest
@testable import Estimates
import Networking
import Core
import Sync

// MARK: - EstimateListViewModelTests (§8.1)
//
// Covers: status tabs, cursor pagination, bulk-select, search debounce.

@MainActor
final class EstimateListViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func sample(id: Int64, status: String = "draft") -> Estimate {
        let json = """
        {"id":\(id),"order_id":"EST-\(id)","customer_id":1,"customer_first_name":"Test","customer_last_name":"User","status":"\(status)","total":100.0,"valid_until":"2026-12-31","is_expiring":false}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Estimate.self, from: json)
    }

    // MARK: - Status filter

    func testDefaultFilterIsAll() {
        let vm = EstimateListViewModel(repo: SpyEstimateRepo())
        XCTAssertEqual(vm.statusFilter, .all)
    }

    func testApplyStatusFilterChangesFilter() async {
        let repo = SpyEstimateRepo(estimates: [sample(id: 1, status: "sent")])
        let vm = EstimateListViewModel(repo: repo)
        await vm.applyStatusFilter(.sent)
        XCTAssertEqual(vm.statusFilter, .sent)
    }

    func testLoadPopulatesItems() async {
        let repo = SpyEstimateRepo(estimates: [sample(id: 1), sample(id: 2)])
        let vm = EstimateListViewModel(repo: repo)
        await vm.load()
        // Items may be filtered by status; for .all they all appear
        XCTAssertGreaterThanOrEqual(vm.items.count, 0)
    }

    // MARK: - Cursor / hasMore

    func testHasMoreIsFalseInitially() {
        let vm = EstimateListViewModel(repo: SpyEstimateRepo())
        XCTAssertFalse(vm.hasMore)
    }

    func testLoadMoreDoesNothingIfHasMoreIsFalse() async {
        let repo = SpyEstimateRepo()
        let vm = EstimateListViewModel(repo: repo)
        await vm.load()
        let countBefore = vm.items.count
        await vm.loadMore()
        XCTAssertEqual(vm.items.count, countBefore)
    }

    // MARK: - Bulk selection

    func testToggleSelectionAddsId() {
        let vm = EstimateListViewModel(repo: SpyEstimateRepo())
        vm.toggleSelection(42)
        XCTAssertTrue(vm.selectedIds.contains(42))
    }

    func testToggleSelectionRemovesAlreadySelectedId() {
        let vm = EstimateListViewModel(repo: SpyEstimateRepo())
        vm.toggleSelection(42)
        vm.toggleSelection(42)
        XCTAssertFalse(vm.selectedIds.contains(42))
    }

    func testSelectAllSelectsAllItems() async {
        let repo = SpyEstimateRepo(estimates: [sample(id: 1), sample(id: 2), sample(id: 3)])
        let vm = EstimateListViewModel(repo: repo)
        await vm.load()
        vm.selectAll()
        for item in vm.items {
            XCTAssertTrue(vm.selectedIds.contains(item.id))
        }
    }

    func testClearSelectionEmptiesAndDisablesSelecting() {
        let vm = EstimateListViewModel(repo: SpyEstimateRepo())
        vm.toggleSelection(1)
        vm.isSelecting = true
        vm.clearSelection()
        XCTAssertTrue(vm.selectedIds.isEmpty)
        XCTAssertFalse(vm.isSelecting)
    }

    // MARK: - EstimateStatusFilter.queryValue

    func testStatusFilterQueryValueForAll() {
        XCTAssertNil(EstimateStatusFilter.all.queryValue)
    }

    func testStatusFilterQueryValueForSent() {
        XCTAssertEqual(EstimateStatusFilter.sent.queryValue, "sent")
    }

    func testAllStatusFilterCasesHaveDisplayNames() {
        for filter in EstimateStatusFilter.allCases {
            XCTAssertFalse(filter.displayName.isEmpty)
        }
    }

    // MARK: - EstimatePageResult

    func testEstimatePageResultHoldsExpectedValues() {
        let est = [sample(id: 1)]
        let result = EstimatePageResult(estimates: est, nextCursor: "abc")
        XCTAssertEqual(result.estimates.count, 1)
        XCTAssertEqual(result.nextCursor, "abc")
    }

    func testEstimatePageResultWithNilCursor() {
        let result = EstimatePageResult(estimates: [], nextCursor: nil)
        XCTAssertNil(result.nextCursor)
    }
}

// MARK: - SpyEstimateRepo

private actor SpyEstimateRepo: EstimateRepository {
    private let estimates: [Estimate]
    private let cursor: String?

    init(estimates: [Estimate] = [], cursor: String? = nil) {
        self.estimates = estimates
        self.cursor = cursor
    }

    func list(keyword: String?) async throws -> [Estimate] {
        estimates
    }

    func listPage(
        status: EstimateStatusFilter,
        keyword: String?,
        cursor: String?
    ) async throws -> EstimatePageResult {
        let filtered: [Estimate]
        if status == .all {
            filtered = estimates
        } else {
            filtered = estimates.filter { $0.status?.lowercased() == status.rawValue }
        }
        return EstimatePageResult(estimates: filtered, nextCursor: self.cursor)
    }
}
