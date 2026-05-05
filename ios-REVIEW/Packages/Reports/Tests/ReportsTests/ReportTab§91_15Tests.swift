import XCTest
@testable import Reports

// MARK: - ReportTab §91.15 Tests
//
// Covers: ReportTab enum shape, raw values, ReportsViewModel default tab,
// didSet-triggered load on tab change, and loadForActiveTab() tab routing.

@MainActor
final class ReportTab§91_15Tests: XCTestCase {

    // MARK: 1. allCases contains exactly 4 tabs

    func test_allCases_returnsFourTabs() {
        XCTAssertEqual(ReportTab.allCases.count, 4)
        XCTAssertEqual(
            Set(ReportTab.allCases.map(\.rawValue)),
            ["Sales", "Tickets", "Inventory", "Insights"]
        )
    }

    // MARK: 2. Raw value / Identifiable id for .sales

    func test_salesTab_idEqualsRawValue() {
        let tab = ReportTab.sales
        XCTAssertEqual(tab.rawValue, "Sales")
        XCTAssertEqual(tab.id, "Sales")
    }

    // MARK: 3. ReportsViewModel default activeTab is .sales

    func test_viewModel_defaultActiveTab_isSales() {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        XCTAssertEqual(vm.activeTab, .sales)
    }

    // MARK: 4. Setting activeTab = .tickets triggers a load (via didSet Task)

    func test_setActiveTab_tickets_triggersLoad() async throws {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        // Change tab — didSet fires a detached Task; give it a chance to run.
        vm.activeTab = .tickets
        // Yield to the cooperative thread pool so the spawned Task executes.
        await Task.yield()
        // Allow the async load to complete.
        try await Task.sleep(nanoseconds: 50_000_000)  // 50 ms

        let callCount = await stub.ticketsByStatusCallCount
        XCTAssertGreaterThanOrEqual(callCount, 1,
            "Switching to .tickets tab should call getTicketsByStatus at least once")
    }

    // MARK: 5. loadForActiveTab(.inventory) calls inventory endpoint, not sales

    func test_loadForActiveTab_inventory_callsInventoryNotSales() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)

        // Force the tab without triggering didSet's extra task.
        vm.activeTab = .inventory
        // Await the explicit call so we have a deterministic completion point.
        await vm.loadForActiveTab()

        let invCalls = await stub.inventoryReportCallCount
        let salesCalls = await stub.revenueCallCount

        XCTAssertGreaterThanOrEqual(invCalls, 1,
            "loadForActiveTab() for .inventory must call getInventoryReport")
        XCTAssertEqual(salesCalls, 0,
            "loadForActiveTab() for .inventory must NOT call the sales/revenue endpoint")
    }

    // MARK: 6. loadForActiveTab(.sales) calls sales, not inventory

    func test_loadForActiveTab_sales_callsSalesNotInventory() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        // activeTab starts as .sales; call directly for determinism.
        await vm.loadForActiveTab()

        let salesCalls = await stub.revenueCallCount
        let invCalls = await stub.inventoryReportCallCount

        XCTAssertGreaterThanOrEqual(salesCalls, 1,
            "loadForActiveTab() for .sales must call getSalesReport")
        XCTAssertEqual(invCalls, 0,
            "loadForActiveTab() for .sales must NOT call getInventoryReport")
    }

    // MARK: 7. loadForActiveTab sets isLoading = false when done

    func test_loadForActiveTab_setsIsLoadingFalseOnCompletion() async {
        let stub = StubReportsRepository()
        let vm = ReportsViewModel(repository: stub)
        await vm.loadForActiveTab()
        XCTAssertFalse(vm.isLoading,
            "isLoading must be false after loadForActiveTab() completes")
    }
}
