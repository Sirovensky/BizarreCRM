/// PosGateViewModelTests.swift
/// Agent B — Customer Gate (Frame 1)
///
/// ≥10 cases covering:
///   empty-query state, debounce fires once, keystroke cancellation,
///   walk-in route, create-new route, error from repo, pickup load success,
///   pickup load error, existing-customer route, pickup route.

import XCTest
import Customers
import Networking
@testable import Pos

@MainActor
final class PosGateViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        customerRepo: CustomerRepository = PreviewCustomerRepository(),
        ticketsRepo: GateTicketsRepository = PreviewGateTicketsRepository()
    ) -> PosGateViewModel {
        PosGateViewModel(customerRepo: customerRepo, ticketsRepo: ticketsRepo)
    }

    // MARK: 1. Empty-query resets results

    func test_emptyQuery_clearsResults() async throws {
        let vm = makeVM()
        // Seed a previous result to verify it's cleared.
        vm.query = "Sarah"
        // Allow debounce to fire.
        try await Task.sleep(nanoseconds: 350_000_000)
        // Now clear.
        vm.query = ""
        // Give event loop a tick.
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.isSearching)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: 2. Debounce fires once for a single keystroke

    func test_debounce_firesOnce() async throws {
        let counter = CallCounter()
        let repo = CountingCustomerRepository(counter: counter)
        let vm = makeVM(customerRepo: repo)
        vm.query = "M"
        // Wait more than 250 ms to let debounce fire.
        try await Task.sleep(nanoseconds: 400_000_000)
        let count = await counter.count
        XCTAssertEqual(count, 1, "Search should be called exactly once")
    }

    // MARK: 3. Rapid keystrokes cancel previous tasks

    func test_rapidKeystrokes_cancelPreviousSearch() async throws {
        let counter = CallCounter()
        let repo = CountingCustomerRepository(counter: counter)
        let vm = makeVM(customerRepo: repo)
        // Fire 5 keystrokes faster than debounce window.
        for char in ["a", "ab", "abc", "abcd", "abcde"] {
            vm.query = char
            try await Task.sleep(nanoseconds: 50_000_000) // 50 ms between keys
        }
        // Wait for final debounce to settle.
        try await Task.sleep(nanoseconds: 400_000_000)
        let count = await counter.count
        XCTAssertLessThanOrEqual(count, 2, "Rapid keystrokes should collapse into at most 2 calls")
    }

    // MARK: 4. Walk-in route

    func test_walkIn_routeIsFired() {
        let vm = makeVM()
        var capturedRoute: PosGateRoute?
        vm.onRouteSelected = { capturedRoute = $0 }
        vm.selectWalkIn()
        XCTAssertEqual(capturedRoute, .walkIn)
    }

    // MARK: 5. Create-new route

    func test_createNew_routeIsFired() {
        let vm = makeVM()
        var capturedRoute: PosGateRoute?
        vm.onRouteSelected = { capturedRoute = $0 }
        vm.selectCreateNew()
        XCTAssertEqual(capturedRoute, .createNew)
    }

    // MARK: 6. Existing customer route

    func test_existingCustomer_routeIsFired() {
        let vm = makeVM()
        var capturedRoute: PosGateRoute?
        vm.onRouteSelected = { capturedRoute = $0 }
        vm.selectExistingCustomer(id: 42)
        XCTAssertEqual(capturedRoute, .existing(42))
    }

    // MARK: 7. Pickup route

    func test_openPickup_routeIsFired() {
        let vm = makeVM()
        var capturedRoute: PosGateRoute?
        vm.onRouteSelected = { capturedRoute = $0 }
        vm.openPickup(id: 999)
        XCTAssertEqual(capturedRoute, .openPickup(999))
    }

    // MARK: 8. Error from repo surfaces in errorMessage

    func test_repoError_surfacesInErrorMessage() async throws {
        let repo = FailingCustomerRepository(error: URLError(.notConnectedToInternet))
        let vm = makeVM(customerRepo: repo)
        vm.query = "test"
        // Wait for debounce + network call.
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNotNil(vm.errorMessage, "Error from repo should surface as errorMessage")
        XCTAssertTrue(vm.results.isEmpty, "Results should be empty on error")
        XCTAssertFalse(vm.isSearching, "isSearching must be false after error")
    }

    // MARK: 9. Pickup load success

    func test_pickupLoad_success() async throws {
        let pickups = [
            ReadyPickup(id: 1, orderId: "4829", customerName: "Sarah M.", deviceSummary: "iPhone 14 screen", totalCents: 27400),
            ReadyPickup(id: 2, orderId: "4831", customerName: "Marco D.", deviceSummary: "Samsung S23 battery", totalCents: 14200),
            ReadyPickup(id: 3, orderId: "4832", customerName: "Tom K.", deviceSummary: nil, totalCents: 5000),
        ]
        let vm = makeVM(ticketsRepo: PreviewGateTicketsRepository(pickups: pickups))
        await vm.loadPickups()
        XCTAssertEqual(vm.pickupTickets.count, 2, "Strip should show at most 2 tickets")
        XCTAssertEqual(vm.totalPickupCount, 3, "Total count should reflect all pickups")
    }

    // MARK: 10. Pickup load error is non-fatal

    func test_pickupLoad_errorIsNonFatal() async {
        let vm = makeVM(ticketsRepo: FailingGateTicketsRepository())
        await vm.loadPickups()
        // Should not crash, errorMessage stays nil (pickup is optional UI).
        XCTAssertTrue(vm.pickupTickets.isEmpty, "Pickups should be empty after error")
        XCTAssertNil(vm.errorMessage, "Pickup error should NOT overwrite errorMessage (non-fatal)")
    }

    // MARK: 11. Query change with whitespace-only is treated as empty

    func test_whitespaceOnlyQuery_treatedAsEmpty() async throws {
        let vm = makeVM()
        vm.query = "   "
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    // MARK: 12. Route callback fires exactly once per action

    func test_route_callbackFiresOnce() {
        let vm = makeVM()
        var callCount = 0
        vm.onRouteSelected = { _ in callCount += 1 }
        vm.selectWalkIn()
        XCTAssertEqual(callCount, 1)
        vm.selectCreateNew()
        XCTAssertEqual(callCount, 2)
        vm.selectExistingCustomer(id: 7)
        XCTAssertEqual(callCount, 3)
    }

    // MARK: 13. Show all pickups toggles sheet flag

    func test_showAllPickups_setsFlag() {
        let vm = makeVM()
        XCTAssertFalse(vm.isShowingPickupSheet)
        vm.showAllPickups()
        XCTAssertTrue(vm.isShowingPickupSheet)
    }

    // MARK: 14. Results cleared on new empty query after prior search

    func test_resultsCleared_whenQueryBecomesEmpty() async throws {
        let vm = makeVM(customerRepo: PreviewCustomerRepository())
        vm.query = "Sarah"
        try await Task.sleep(nanoseconds: 400_000_000)
        // Sanity: results populated
        XCTAssertFalse(vm.results.isEmpty, "Pre-condition: results should have populated")
        // Now clear query
        vm.query = ""
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.results.isEmpty, "Clearing query must wipe results")
    }
}

// MARK: - Test doubles

/// Thread-safe call counter using an actor.
private actor CallCounter {
    private(set) var count: Int = 0
    func increment() { count += 1 }
}

/// A CustomerRepository that counts how many times `list(keyword:)` is called.
private struct CountingCustomerRepository: CustomerRepository {
    let counter: CallCounter

    func list(keyword: String?) async throws -> [CustomerSummary] {
        await counter.increment()
        // Simulate a tiny network delay so the debounce timing tests are realistic.
        try await Task.sleep(nanoseconds: 5_000_000) // 5 ms
        return []
    }

    func update(id: Int64, _ req: UpdateCustomerRequest) async throws -> CustomerDetail {
        throw URLError(.unsupportedURL)
    }
}
