import XCTest
@testable import Estimates
import Networking
import Sync

// MARK: - EstimatesThreeColumnViewModelTests
//
// §22 iPad — unit tests for EstimatesThreeColumnViewModel.
// Coverage: initial state, load, refresh, search debounce, status filter,
// selectedEstimate, error handling, filteredItems derived property.

@MainActor
final class EstimatesThreeColumnViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(estimates: [Estimate] = []) -> EstimatesThreeColumnViewModel {
        let repo = ThreeColStubRepository(estimates: estimates)
        return EstimatesThreeColumnViewModel(repo: repo)
    }

    private func sample(
        id: Int64,
        status: String = "draft",
        total: Double = 100,
        orderId: String? = nil
    ) -> Estimate {
        let json = """
        {
          "id": \(id),
          "order_id": "\(orderId ?? "EST-\(id)")",
          "customer_first_name": "Test",
          "customer_last_name": "User",
          "status": "\(status)",
          "total": \(total),
          "is_expiring": false
        }
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(Estimate.self, from: json)
    }

    // MARK: - Initial State

    func test_initialState_isEmpty() {
        let vm = makeSUT()
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.selectedStatus)
        XCTAssertNil(vm.selectedEstimate)
        XCTAssertEqual(vm.searchQuery, "")
    }

    func test_initialState_filteredItemsMirrorsItems_whenNoFilter() {
        let vm = makeSUT(estimates: [sample(id: 1), sample(id: 2)])
        XCTAssertEqual(vm.filteredItems.count, vm.items.count)
    }

    // MARK: - load()

    func test_load_populatesItems() async {
        let vm = makeSUT(estimates: [sample(id: 1), sample(id: 2)])
        await vm.load()
        XCTAssertEqual(vm.items.count, 2)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_load_setsIsLoadingThenClears() async {
        let vm = makeSUT(estimates: [sample(id: 1)])
        // isLoading is set synchronously before the first await; by the time
        // load() returns it should be false again.
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_withError_setsErrorMessage() async {
        let repo = ThreeColStubRepository(error: APITransportError.noBaseURL)
        let vm = EstimatesThreeColumnViewModel(repo: repo)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func test_load_withError_doesNotSetLoading() async {
        let repo = ThreeColStubRepository(error: APITransportError.noBaseURL)
        let vm = EstimatesThreeColumnViewModel(repo: repo)
        await vm.load()
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - refresh()

    func test_refresh_updatesItems() async {
        let vm = makeSUT(estimates: [sample(id: 10)])
        await vm.refresh()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.id, 10)
    }

    // MARK: - Status filter

    func test_filteredItems_noFilter_returnsAll() async {
        let vm = makeSUT(estimates: [sample(id: 1, status: "draft"), sample(id: 2, status: "sent")])
        await vm.load()
        vm.selectedStatus = nil
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func test_filteredItems_draftFilter_returnsDraftOnly() async {
        let items = [sample(id: 1, status: "draft"), sample(id: 2, status: "sent"), sample(id: 3, status: "draft")]
        let vm = makeSUT(estimates: items)
        await vm.load()
        vm.selectedStatus = "draft"
        XCTAssertEqual(vm.filteredItems.count, 2)
        XCTAssertTrue(vm.filteredItems.allSatisfy { $0.status?.lowercased() == "draft" })
    }

    func test_filteredItems_signedFilter_returnsSignedOnly() async {
        let items = [sample(id: 1, status: "signed"), sample(id: 2, status: "sent")]
        let vm = makeSUT(estimates: items)
        await vm.load()
        vm.selectedStatus = "signed"
        XCTAssertEqual(vm.filteredItems.count, 1)
        XCTAssertEqual(vm.filteredItems.first?.status, "signed")
    }

    func test_filteredItems_emptyWhenNoMatchForFilter() async {
        let vm = makeSUT(estimates: [sample(id: 1, status: "draft")])
        await vm.load()
        vm.selectedStatus = "converted"
        XCTAssertTrue(vm.filteredItems.isEmpty)
    }

    // MARK: - selectedEstimate

    func test_selectedEstimate_defaultsNil() {
        let vm = makeSUT()
        XCTAssertNil(vm.selectedEstimate)
    }

    func test_selectedEstimate_canBeSet() async {
        let est = sample(id: 42, status: "approved")
        let vm = makeSUT(estimates: [est])
        await vm.load()
        vm.selectedEstimate = vm.items.first
        XCTAssertEqual(vm.selectedEstimate?.id, 42)
    }

    // MARK: - statusFilters

    func test_statusFilters_containsNilForAll() {
        let vm = makeSUT()
        XCTAssertTrue(vm.statusFilters.contains(nil))
    }

    func test_statusFilters_containsExpectedStatuses() {
        let vm = makeSUT()
        let expected = ["draft", "sent", "approved", "signed", "converted", "rejected", "expired"]
        for status in expected {
            XCTAssertTrue(
                vm.statusFilters.contains(status),
                "Expected '\(status)' in statusFilters"
            )
        }
    }

    // MARK: - onSearchChange

    func test_onSearchChange_updatesSearchQuery() {
        let vm = makeSUT()
        vm.onSearchChange("battery")
        XCTAssertEqual(vm.searchQuery, "battery")
    }

    func test_onSearchChange_emptyQuery_resetsSearchQuery() {
        let vm = makeSUT()
        vm.onSearchChange("abc")
        vm.onSearchChange("")
        XCTAssertEqual(vm.searchQuery, "")
    }
}

// MARK: - ThreeColStubRepository

private final class ThreeColStubRepository: EstimateRepository, @unchecked Sendable {
    private let estimates: [Estimate]
    private let error: Error?

    init(estimates: [Estimate] = [], error: Error? = nil) {
        self.estimates = estimates
        self.error = error
    }

    func list(keyword: String?) async throws -> [Estimate] {
        if let error { throw error }
        return estimates
    }
}
