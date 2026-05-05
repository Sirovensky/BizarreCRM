import XCTest
@testable import Invoices
@testable import Networking

// §7.1 InvoiceFilterSheet — 5-axis filter model + ViewModel wiring tests

final class InvoiceFilterSheetTests: XCTestCase {

    // MARK: - InvoiceListFilter model

    func testDefaultFilterIsNotActive() {
        let filter = InvoiceListFilter()
        XCTAssertFalse(filter.isActive, "Empty filter should not be active")
        XCTAssertTrue(filter.queryItems.isEmpty, "Empty filter should produce no query items")
    }

    func testCustomerNameProducesQueryItem() {
        var filter = InvoiceListFilter()
        filter.customerName = "Alice"
        XCTAssertTrue(filter.isActive)
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "customer" && $0.value == "Alice" }))
    }

    func testDateRangeProducesQueryItems() {
        var filter = InvoiceListFilter()
        let now = Date()
        filter.dateRangeStart = now
        filter.dateRangeEnd = now
        XCTAssertTrue(filter.isActive)
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "date_from" }))
        XCTAssertTrue(items.contains(where: { $0.name == "date_to" }))
    }

    func testAmountRangeProducesQueryItems() {
        var filter = InvoiceListFilter()
        filter.amountMin = 10.0
        filter.amountMax = 500.0
        XCTAssertTrue(filter.isActive)
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "amount_min" && $0.value == "10.00" }))
        XCTAssertTrue(items.contains(where: { $0.name == "amount_max" && $0.value == "500.00" }))
    }

    func testPaymentMethodProducesQueryItem() {
        var filter = InvoiceListFilter()
        filter.paymentMethod = InvoicePaymentMethodFilter.cash.rawValue
        XCTAssertTrue(filter.isActive)
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "payment_method" && $0.value == "cash" }))
    }

    func testCreatedByProducesQueryItem() {
        var filter = InvoiceListFilter()
        filter.createdBy = "Bob"
        XCTAssertTrue(filter.isActive)
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "created_by" && $0.value == "Bob" }))
    }

    func testAllAxesProduceCorrectQueryItemCount() {
        var filter = InvoiceListFilter()
        filter.dateRangeStart = Date()
        filter.dateRangeEnd = Date()
        filter.customerName = "Alice"
        filter.amountMin = 10.0
        filter.amountMax = 500.0
        filter.paymentMethod = "card"
        filter.createdBy = "Bob"
        let items = filter.queryItems
        XCTAssertEqual(items.count, 7, "7 axes → 7 query items")
    }

    func testPartiallyNilAmountRangeOnlyEmitsPresentAxis() {
        var filter = InvoiceListFilter()
        filter.amountMin = 25.0
        // amountMax nil
        let items = filter.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "amount_min" }))
        XCTAssertFalse(items.contains(where: { $0.name == "amount_max" }))
    }

    // MARK: - InvoicePaymentMethodFilter

    func testAllPaymentMethodsHaveDisplayNames() {
        for method in InvoicePaymentMethodFilter.allCases {
            XCTAssertFalse(method.displayName.isEmpty, "\(method.rawValue) should have a non-empty display name")
        }
    }

    func testPaymentMethodsHaveUniqueRawValues() {
        let rawValues = InvoicePaymentMethodFilter.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count, "Payment method raw values must be unique")
    }

    // MARK: - ViewModel integration

    @MainActor
    func testHasActiveFilterReflectsState() {
        let repo = StubInvoiceRepository()
        let vm = InvoiceListViewModel(repo: repo)
        XCTAssertFalse(vm.hasActiveFilter, "Default VM should have no active filter")

        var filter = InvoiceListFilter()
        filter.customerName = "Jane"
        vm.advancedFilter = filter
        XCTAssertTrue(vm.hasActiveFilter, "VM should report active filter when customerName is set")
    }

    @MainActor
    func testApplyAdvancedFilterUpdatesState() async {
        let repo = StubInvoiceRepository()
        let vm = InvoiceListViewModel(repo: repo)
        var filter = InvoiceListFilter()
        filter.paymentMethod = "card"

        await vm.applyAdvancedFilter(filter)

        XCTAssertEqual(vm.advancedFilter.paymentMethod, "card")
        XCTAssertTrue(vm.hasActiveFilter)
    }

    @MainActor
    func testClearAdvancedFilterResetsState() async {
        let repo = StubInvoiceRepository()
        let vm = InvoiceListViewModel(repo: repo)
        var filter = InvoiceListFilter()
        filter.paymentMethod = "cash"
        await vm.applyAdvancedFilter(filter)

        await vm.clearAdvancedFilter()

        XCTAssertFalse(vm.hasActiveFilter)
        XCTAssertNil(vm.advancedFilter.paymentMethod)
    }

    @MainActor
    func testAdvancedFilterPassedToRepo() async {
        let repo = StubInvoiceRepository()
        let vm = InvoiceListViewModel(repo: repo)

        var filter = InvoiceListFilter()
        filter.createdBy = "Alice"
        await vm.applyAdvancedFilter(filter)

        XCTAssertEqual(repo.lastAdvancedFilter?.createdBy, "Alice",
                       "Repository should receive the advanced filter")
    }
}

// MARK: - Stub repository for ViewModel tests

@MainActor
private final class StubInvoiceRepository: InvoiceRepository, @unchecked Sendable {
    var listResult: [InvoiceSummary] = []
    var lastAdvancedFilter: InvoiceListFilter?

    func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        listResult
    }

    func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?,
        advancedFilter: InvoiceListFilter
    ) async throws -> InvoicesListResponse {
        lastAdvancedFilter = advancedFilter
        return InvoicesListResponse(invoices: listResult, pagination: nil)
    }
}
