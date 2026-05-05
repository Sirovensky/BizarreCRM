import XCTest
@testable import Expenses
@testable import Networking

// MARK: - Mock for list tests
// NOTE: MockExpenseListAPIClient is already defined in ExpenseCachedRepositoryTests.swift
// We define a separate lean mock here specifically for ExpenseListViewModel tests so
// the delete path is also testable without coupling to the repo mock.

actor MockListAPIClient: APIClient {
    enum ListOutcome {
        case success(ExpensesListResponse)
        case failure(Error)
    }
    enum DeleteOutcome {
        case success
        case failure(Error)
    }

    var listOutcome: ListOutcome = .success(ExpensesListResponse(expenses: [], summary: nil))
    var deleteOutcome: DeleteOutcome = .success

    private(set) var listCallCount: Int = 0
    private(set) var deleteCallCount: Int = 0
    private(set) var lastListQuery: [URLQueryItem]? = nil

    func setListOutcome(_ o: ListOutcome) { listOutcome = o }
    func setDeleteOutcome(_ o: DeleteOutcome) { deleteOutcome = o }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/expenses", T.self == ExpensesListResponse.self {
            listCallCount += 1
            lastListQuery = query
            switch listOutcome {
            case .success(let resp):
                guard let cast = resp as? T else { throw MockError.typeMismatch }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw MockError.notConfigured
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw MockError.notConfigured }

    func delete(_ path: String) async throws {
        deleteCallCount += 1
        switch deleteOutcome {
        case .success: return
        case .failure(let err): throw err
        }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw MockError.notConfigured }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) {}
}

// MARK: - Helpers

private func makeListResponse(
    expenses: [Expense] = [],
    totalAmount: Double = 0,
    totalCount: Int = 0
) -> ExpensesListResponse {
    let summary = ExpensesListResponse.Summary(totalAmount: totalAmount, totalCount: totalCount)
    return ExpensesListResponse(expenses: expenses, summary: summary)
}

// MARK: - ExpenseListViewModelTests

@MainActor
final class ExpenseListViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateIsEmpty() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertNil(vm.summary)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func testInitialFilterIsEmpty() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        XCTAssertFalse(vm.isFiltered)
    }

    // MARK: - Successful load

    func testLoadPopulatesItems() async {
        let api = MockListAPIClient()
        let expenses = [
            Expense.fixture(id: 1, category: "office", amount: 50),
            Expense.fixture(id: 2, category: "travel", amount: 200)
        ]
        await api.setListOutcome(.success(makeListResponse(expenses: expenses, totalAmount: 250, totalCount: 2)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertNil(vm.errorMessage)
    }

    func testLoadPopulatesSummary() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.success(makeListResponse(totalAmount: 99.99, totalCount: 3)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.summary?.totalAmount ?? 0, 99.99, accuracy: 0.001)
        XCTAssertEqual(vm.summary?.totalCount, 3)
    }

    func testLoadCallsAPIOnce() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.success(makeListResponse()))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        let count = await api.listCallCount
        XCTAssertEqual(count, 1)
    }

    func testLoadClearsErrorOnSuccess() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.failure(MockError.network))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)

        await api.setListOutcome(.success(makeListResponse()))
        await vm.load()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Failed load

    func testLoadFailureSetsErrorMessage() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.failure(MockError.network))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testLoadFailureDoesNotClearItems() async {
        let api = MockListAPIClient()
        let expenses = [Expense.fixture(id: 1)]
        await api.setListOutcome(.success(makeListResponse(expenses: expenses, totalCount: 1)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)

        // Second load fails — items stay populated from previous fetch
        await api.setListOutcome(.failure(MockError.network))
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)
    }

    // MARK: - Summary header data

    func testSummaryAvailableAfterLoad() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.success(makeListResponse(totalAmount: 500, totalCount: 5)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.summary)
    }

    func testSummaryNilWhenServerReturnsNoSummary() async {
        let api = MockListAPIClient()
        let resp = ExpensesListResponse(expenses: [], summary: nil)
        await api.setListOutcome(.success(resp))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertNil(vm.summary)
    }

    // MARK: - removeItem (optimistic delete)

    func testRemoveItemReducesCount() async {
        let api = MockListAPIClient()
        let expenses = [
            Expense.fixture(id: 10),
            Expense.fixture(id: 20),
            Expense.fixture(id: 30)
        ]
        await api.setListOutcome(.success(makeListResponse(expenses: expenses, totalCount: 3)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(vm.items.count, 3)

        vm.removeItem(id: 20)
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertFalse(vm.items.contains { $0.id == 20 })
    }

    func testRemoveItemNonexistentIdIsNoOp() async {
        let api = MockListAPIClient()
        let expenses = [Expense.fixture(id: 1), Expense.fixture(id: 2)]
        await api.setListOutcome(.success(makeListResponse(expenses: expenses, totalCount: 2)))
        let vm = ExpenseListViewModel(api: api)
        await vm.load()

        vm.removeItem(id: 999)
        XCTAssertEqual(vm.items.count, 2)
    }

    // MARK: - isFiltered

    func testIsFilteredFalseWithDefaultFilter() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        XCTAssertFalse(vm.isFiltered)
    }

    func testIsFilteredTrueAfterApplyingCategory() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        vm.filter = ExpenseListFilter(category: "travel")
        XCTAssertTrue(vm.isFiltered)
    }

    func testIsFilteredTrueAfterApplyingStatus() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        vm.filter = ExpenseListFilter(status: "approved")
        XCTAssertTrue(vm.isFiltered)
    }

    func testIsFilteredFalseAfterClearFilter() {
        let api = MockListAPIClient()
        let vm = ExpenseListViewModel(api: api)
        vm.filter = ExpenseListFilter(category: "tools", status: "pending")
        XCTAssertTrue(vm.isFiltered)
        vm.clearFilter()
        XCTAssertFalse(vm.isFiltered)
    }

    // MARK: - forceRefresh

    func testForceRefreshCallsAPI() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.success(makeListResponse()))
        let vm = ExpenseListViewModel(api: api)
        await vm.forceRefresh()
        let count = await api.listCallCount
        XCTAssertEqual(count, 1)
    }

    func testForceRefreshUpdatesItems() async {
        let api = MockListAPIClient()
        await api.setListOutcome(.success(makeListResponse(expenses: [Expense.fixture(id: 5)], totalCount: 1)))
        let vm = ExpenseListViewModel(api: api)
        await vm.forceRefresh()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, 5)
    }
}

// MARK: - ExpenseSummaryHeaderView category total tests

final class ExpenseSummaryHeaderViewTests: XCTestCase {

    func testCategoryTotalsEmpty() {
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: [])
        XCTAssertTrue(totals.isEmpty)
    }

    func testCategoryTotalsSingleCategory() {
        let expenses = [
            Expense.fixture(id: 1, category: "office", amount: 50),
            Expense.fixture(id: 2, category: "office", amount: 30)
        ]
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].id, "office")
        XCTAssertEqual(totals[0].total, 80, accuracy: 0.001)
        XCTAssertEqual(totals[0].count, 2)
    }

    func testCategoryTotalsMultipleCategories() {
        let expenses = [
            Expense.fixture(id: 1, category: "travel", amount: 200),
            Expense.fixture(id: 2, category: "office", amount: 50),
            Expense.fixture(id: 3, category: "travel", amount: 100)
        ]
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.count, 2)
        // Sorted by total descending
        XCTAssertEqual(totals[0].id, "travel")
        XCTAssertEqual(totals[0].total, 300, accuracy: 0.001)
        XCTAssertEqual(totals[1].id, "office")
        XCTAssertEqual(totals[1].total, 50, accuracy: 0.001)
    }

    func testCategoryTotalsNilCategoryFallsToOther() {
        let expenses = [Expense.fixture(id: 1, category: nil, amount: 25)]
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].id, "Other")
    }

    func testCategoryTotalsNilAmountTreatedAsZero() {
        let expenses = [Expense.fixture(id: 1, category: "tools", amount: nil)]
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].total, 0, accuracy: 0.001)
    }

    func testCategoryTotalsCountMatchesInputLength() {
        let categories = ["rent", "tools", "fuel", "meals", "software"]
        let expenses = categories.enumerated().map { i, cat in
            Expense.fixture(id: Int64(i + 1), category: cat, amount: Double((i + 1) * 10))
        }
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.count, categories.count)
    }

    func testCategoryTotalsSortedDescending() {
        let expenses = [
            Expense.fixture(id: 1, category: "a", amount: 10),
            Expense.fixture(id: 2, category: "b", amount: 100),
            Expense.fixture(id: 3, category: "c", amount: 50)
        ]
        let totals = ExpenseSummaryHeaderView.categoryTotals(from: expenses)
        XCTAssertEqual(totals.map(\.id), ["b", "c", "a"])
    }
}
