import XCTest
@testable import Customers
import Networking

// MARK: - CustomerListViewModelCachedTests

/// Tests exercising `CustomerListViewModel` with a cached repository:
/// - `refresh()` calls `forceRefresh()` on the cached repo (pull-to-refresh round-trip).
/// - `lastSyncedAt` is updated after load and refresh.
/// - `refresh()` with a non-cached repo falls back to `fetch()`.

@MainActor
final class CustomerListViewModelCachedTests: XCTestCase {

    // MARK: - lastSyncedAt

    func test_lastSyncedAt_isNilInitially() {
        let repo = StubCachedCustomerRepo()
        let vm = CustomerListViewModel(repo: repo)
        XCTAssertNil(vm.lastSyncedAt)
    }

    func test_lastSyncedAt_isSetAfterLoad() async {
        let repo = StubCachedCustomerRepo()
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.lastSyncedAt)
    }

    // MARK: - Pull-to-refresh round-trip

    func test_refresh_callsForceRefreshOnCachedRepo() async {
        let repo = StubCachedCustomerRepo()
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        await vm.refresh()
        let count = await repo.forceRefreshCount
        XCTAssertEqual(count, 1, "pull-to-refresh must call forceRefresh() on the cached repo")
    }

    func test_refresh_updatesLastSyncedAt() async {
        let repo = StubCachedCustomerRepo()
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        let before = Date()
        await vm.refresh()
        XCTAssertNotNil(vm.lastSyncedAt)
        XCTAssertGreaterThanOrEqual(vm.lastSyncedAt!, before)
    }

    func test_refresh_updatesCustomers() async {
        let repo = StubCachedCustomerRepo(customerCount: 3)
        let vm = CustomerListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.customers.count, 3)

        await repo.setCustomerCount(8)
        await vm.refresh()
        XCTAssertEqual(vm.customers.count, 8)
    }

    func test_refresh_setsErrorMessage_onFailure() async {
        let repo = StubCachedCustomerRepo(shouldFail: true)
        let vm = CustomerListViewModel(repo: repo)
        await vm.refresh()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Non-cached fallback

    func test_refresh_withNonCachedRepo_fallsBackToFetch() async {
        let repo = PlainStubCustomerRepo(customerCount: 5)
        let vm = CustomerListViewModel(repo: repo)
        await vm.refresh()
        XCTAssertEqual(vm.customers.count, 5)
    }
}

// MARK: - Stubs

private actor StubCachedCustomerRepo: CustomerCachedRepository {
    private var customerCount: Int
    private var shouldFail: Bool
    private(set) var forceRefreshCount: Int = 0
    private var syncedAt: Date?

    init(customerCount: Int = 2, shouldFail: Bool = false) {
        self.customerCount = customerCount
        self.shouldFail = shouldFail
    }

    func setCustomerCount(_ count: Int) {
        customerCount = count
    }

    var lastSyncedAt: Date? { syncedAt }

    func list(keyword: String?) async throws -> [CustomerSummary] {
        if shouldFail { throw CVMTestError.boom }
        syncedAt = Date()
        return makeCustomers(count: customerCount)
    }

    func forceRefresh(keyword: String?) async throws -> [CustomerSummary] {
        forceRefreshCount += 1
        if shouldFail { throw CVMTestError.boom }
        syncedAt = Date()
        return makeCustomers(count: customerCount)
    }

    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw CVMTestError.boom
    }

    private func makeCustomers(count: Int) -> [CustomerSummary] {
        (0..<count).map { index in
            let json = """
            { "id": \(index), "first_name": "User", "last_name": "\(index)" }
            """.data(using: .utf8)!
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try! decoder.decode(CustomerSummary.self, from: json)
        }
    }
}

private actor PlainStubCustomerRepo: CustomerRepository {
    private let customerCount: Int

    init(customerCount: Int) {
        self.customerCount = customerCount
    }

    func list(keyword: String?) async throws -> [CustomerSummary] {
        (0..<customerCount).map { index in
            let json = """
            { "id": \(index), "first_name": "User", "last_name": "\(index)" }
            """.data(using: .utf8)!
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try! decoder.decode(CustomerSummary.self, from: json)
        }
    }

    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw CVMTestError.boom
    }
}

private enum CVMTestError: Error, LocalizedError {
    case boom
    var errorDescription: String? { "boom" }
}
