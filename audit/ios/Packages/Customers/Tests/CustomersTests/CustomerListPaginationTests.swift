import XCTest
@testable import Customers
import Networking

// MARK: - CustomerListPaginationTests
//
// §5.1 cursor pagination, sort, filter, bulk operations, and §5.4 conflict banner.

@MainActor
final class CustomerListPaginationTests: XCTestCase {

    // MARK: - Cursor pagination

    func test_load_populatesCustomersFromPage() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 10), nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.customers.count, 10)
        XCTAssertFalse(vm.hasMore)
        XCTAssertNil(repo.lastCursor, "first load must not send a cursor")
    }

    func test_load_setsHasMore_whenNextCursorPresent() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 5), nextCursor: "abc123")
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertTrue(vm.hasMore)
    }

    func test_load_clearsExistingCustomers_onReload() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 3), nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.customers.count, 3)

        await repo.setCustomers(makeCustomers(count: 7))
        await vm.load()
        XCTAssertEqual(vm.customers.count, 7, "reload must replace, not append")
    }

    func test_loadMoreIfNeeded_appendsNextPage() async {
        let firstPage = makeCustomers(count: 5)
        let secondPage = makeCustomers(count: 3, startingAt: 5)
        let repo = PaginationStubRepo(customers: firstPage, nextCursor: "page2")
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()

        // Switch repo to return second page on next call.
        await repo.setCustomers(secondPage)
        await repo.setNextCursor(nil)

        // Trigger loadMore with the last item.
        if let last = vm.customers.last {
            await vm.loadMoreIfNeeded(currentItem: last)
        }
        // Should now have first + second page.
        XCTAssertEqual(vm.customers.count, 8)
        XCTAssertFalse(vm.hasMore)
    }

    // MARK: - Sort

    func test_sort_serverKeyMapping() {
        XCTAssertEqual(CustomerSortOrder.name.serverKey, "name_asc")
        XCTAssertEqual(CustomerSortOrder.nameDesc.serverKey, "name_desc")
        XCTAssertEqual(CustomerSortOrder.mostTickets.serverKey, "tickets_desc")
        XCTAssertEqual(CustomerSortOrder.mostRevenue.serverKey, "revenue_desc")
        XCTAssertEqual(CustomerSortOrder.lastVisit.serverKey, "last_visit_desc")
        XCTAssertEqual(CustomerSortOrder.ltvTier.serverKey, "ltv_desc")
        XCTAssertEqual(CustomerSortOrder.churnRisk.serverKey, "churn_desc")
    }

    func test_sortOrder_passedInQuery() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 2), nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        vm.sortOrder = .mostRevenue
        await vm.load()
        let sort = await repo.lastSort
        XCTAssertEqual(sort, "revenue_desc")
    }

    // MARK: - Filter

    func test_filter_isActiveWhenFieldsSet() {
        var filter = CustomerListFilter()
        XCTAssertFalse(filter.isActive)
        filter.ltvTier = "vip"
        XCTAssertTrue(filter.isActive)
    }

    func test_filter_passedInQuery() async {
        let repo = PaginationStubRepo(customers: [], nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        vm.filter.ltvTier = "vip"
        vm.filter.balanceGtZero = true
        await vm.load()
        let ltvTier = await repo.lastLtvTier
        let balance = await repo.lastBalanceGtZero
        XCTAssertEqual(ltvTier, "vip")
        XCTAssertTrue(balance)
    }

    // MARK: - Bulk select

    func test_toggleBulkSelect_enablesBulkMode() {
        let repo = PaginationStubRepo(customers: [], nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        XCTAssertFalse(vm.isBulkSelecting)
        vm.toggleBulkSelect()
        XCTAssertTrue(vm.isBulkSelecting)
    }

    func test_toggleSelection_addsAndRemovesId() {
        let repo = PaginationStubRepo(customers: [], nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        vm.toggleSelection(id: 42)
        XCTAssertTrue(vm.selectedIds.contains(42))
        vm.toggleSelection(id: 42)
        XCTAssertFalse(vm.selectedIds.contains(42))
    }

    func test_bulkTag_callsRepo() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 3), nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        vm.toggleBulkSelect()
        for c in vm.customers { vm.toggleSelection(id: c.id) }

        await vm.bulkTag(tag: "vip")

        let tagCount = await repo.bulkTagCount
        XCTAssertEqual(tagCount, 1, "bulkTag must call repo.bulkTag exactly once")
        XCTAssertFalse(vm.isBulkSelecting, "should exit bulk mode after tag")
        XCTAssertTrue(vm.selectedIds.isEmpty)
    }

    func test_bulkDelete_removesCustomersOptimistically() async {
        let repo = PaginationStubRepo(customers: makeCustomers(count: 4), nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.customers.count, 4)

        vm.toggleBulkSelect()
        // Select first 2.
        for c in vm.customers.prefix(2) { vm.toggleSelection(id: c.id) }

        let deleted = await vm.bulkDelete()
        XCTAssertEqual(deleted.count, 2, "must return the deleted rows for undo")
        XCTAssertEqual(vm.customers.count, 2, "customers must shrink by 2 immediately")
    }

    // MARK: - §5.4 Concurrent-edit conflict

    func test_reportConflict_setsBanner() {
        let repo = PaginationStubRepo(customers: [], nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        XCTAssertFalse(vm.concurrentEditConflict)
        vm.reportConcurrentEdit()
        XCTAssertTrue(vm.concurrentEditConflict)
    }

    func test_dismissConflict_clearsBanner() {
        let repo = PaginationStubRepo(customers: [], nextCursor: nil)
        let vm = CustomerListViewModel(repo: repo)
        vm.reportConcurrentEdit()
        vm.dismissConflictBanner()
        XCTAssertFalse(vm.concurrentEditConflict)
    }

    // MARK: - Helpers

    private func makeCustomers(count: Int, startingAt start: Int = 0) -> [CustomerSummary] {
        (start..<(start + count)).map { index in
            let json = """
            { "id": \(index), "first_name": "User", "last_name": "\(index)" }
            """.data(using: .utf8)!
            return try! JSONDecoder().decode(CustomerSummary.self, from: json)
        }
    }
}

// MARK: - PaginationStubRepo

private actor PaginationStubRepo: CustomerRepository {
    private var customers: [CustomerSummary]
    private var nextCursor: String?
    private(set) var lastCursor: String?
    private(set) var lastSort: String?
    private(set) var lastLtvTier: String?
    private(set) var lastBalanceGtZero: Bool = false
    private(set) var bulkTagCount: Int = 0
    private(set) var bulkDeleteCount: Int = 0

    init(customers: [CustomerSummary], nextCursor: String?) {
        self.customers = customers
        self.nextCursor = nextCursor
    }

    func setCustomers(_ c: [CustomerSummary]) { customers = c }
    func setNextCursor(_ c: String?) { nextCursor = c }

    func list(keyword: String?) async throws -> [CustomerSummary] { customers }

    func listPage(cursor: String?, query: CustomerListQuery) async throws -> CustomerCursorPage {
        lastCursor = cursor
        lastSort = query.sort
        lastLtvTier = query.ltvTier
        lastBalanceGtZero = query.balanceGtZero
        return CustomerCursorPage(customers: customers, nextCursor: nextCursor, stats: nil)
    }

    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw NSError(domain: "Stub", code: 0)
    }

    func bulkTag(_ req: BulkTagRequest) async throws -> BulkOperationResult {
        bulkTagCount += 1
        return BulkOperationResult(affected: req.customerIds.count)
    }

    func bulkDelete(_ req: BulkDeleteRequest) async throws -> BulkOperationResult {
        bulkDeleteCount += 1
        customers.removeAll { req.customerIds.contains($0.id) }
        return BulkOperationResult(affected: req.customerIds.count)
    }
}
