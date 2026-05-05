import XCTest
import GRDB
import Core
@testable import Search

@MainActor
final class EntitySearchViewModelTests: XCTestCase {

    private var db: DatabaseQueue!
    private var ftsStore: FTSIndexStore!
    private var vm: EntitySearchViewModel!

    override func setUp() async throws {
        db = try FTSMigration.openInMemory()
        ftsStore = FTSIndexStore(db: db)
        // Use 0 ms debounce so tests don't wait
        vm = EntitySearchViewModel(store: ftsStore, debounceMs: 0)
    }

    override func tearDown() async throws {
        vm = nil
        ftsStore = nil
        db = nil
    }

    // MARK: - Initial state

    func test_initialState_hitsEmpty() {
        XCTAssertTrue(vm.hits.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - clearQuery

    func test_clearQuery_resetsState() async throws {
        let ticket = Ticket(
            id: 1, displayId: "T-1", customerId: 1,
            customerName: "Alice", status: .inProgress,
            createdAt: .now, updatedAt: .now
        )
        try await ftsStore.indexTicket(ticket)

        vm.query = "Alice"
        // Allow debounce to fire
        try await Task.sleep(nanoseconds: 10_000_000)

        vm.clearQuery()
        XCTAssertEqual(vm.query, "")
        XCTAssertTrue(vm.hits.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Query → hits

    func test_queryChange_returnsHits() async throws {
        let ticket = Ticket(
            id: 2, displayId: "T-2", customerId: 1,
            customerName: "Bob Smith", status: .ready,
            deviceSummary: "Samsung",
            createdAt: .now, updatedAt: .now
        )
        try await ftsStore.indexTicket(ticket)

        vm.onQueryChanged("Samsung")
        // Allow async search to run (debounce = 0ms + task yield)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(vm.hits.isEmpty, "Should find indexed ticket")
    }

    // MARK: - Filter

    func test_entityFilter_restrictsResults() async throws {
        let ticket = Ticket(
            id: 3, displayId: "T-3", customerId: 1,
            customerName: "Charlie", status: .intake,
            createdAt: .now, updatedAt: .now
        )
        let customer = Customer(
            id: 3, firstName: "Charlie", lastName: "Brown",
            createdAt: .now, updatedAt: .now
        )
        try await ftsStore.indexTicket(ticket)
        try await ftsStore.indexCustomer(customer)

        vm.selectedFilter = .customers
        vm.onQueryChanged("Charlie")
        try await Task.sleep(nanoseconds: 50_000_000)

        let entities = Set(vm.hits.map { $0.entity })
        XCTAssertTrue(entities.subtracting(["customers"]).isEmpty,
                      "With customers filter, only customer hits should appear")
    }

    // MARK: - Empty query

    func test_emptyQuery_clearsHits() async throws {
        vm.onQueryChanged("something")
        try await Task.sleep(nanoseconds: 50_000_000)

        vm.onQueryChanged("")
        XCTAssertTrue(vm.hits.isEmpty)
        XCTAssertFalse(vm.isLoading)
    }
}
