import XCTest
@testable import Inventory
import Networking

// MARK: - InventorySortFilterTests

/// §6.1 — Tests for `InventorySortOption`, `InventoryAdvancedFilter`,
/// and the updated `InventoryListViewModel` sort/filter wiring.
final class InventorySortFilterTests: XCTestCase {

    // MARK: - InventorySortOption

    func testSortOptionQueryItems_nameAsc() {
        let items = InventorySortOption.nameAsc.queryItems
        XCTAssertEqual(items.first(where: { $0.name == "sort_by" })?.value, "name")
        XCTAssertEqual(items.first(where: { $0.name == "sort_dir" })?.value, "asc")
    }

    func testSortOptionQueryItems_stockDesc() {
        let items = InventorySortOption.stockDesc.queryItems
        XCTAssertEqual(items.first(where: { $0.name == "sort_by" })?.value, "in_stock")
        XCTAssertEqual(items.first(where: { $0.name == "sort_dir" })?.value, "desc")
    }

    func testSortOptionQueryItems_priceAsc() {
        let items = InventorySortOption.priceAsc.queryItems
        XCTAssertEqual(items.first(where: { $0.name == "sort_by" })?.value, "retail_price")
        XCTAssertEqual(items.first(where: { $0.name == "sort_dir" })?.value, "asc")
    }

    func testSortOptionQueryItems_margin() {
        let items = InventorySortOption.margin.queryItems
        XCTAssertEqual(items.first(where: { $0.name == "sort_by" })?.value, "margin")
    }

    func testAllSortOptionsHaveDisplayName() {
        for opt in InventorySortOption.allCases {
            XCTAssertFalse(opt.displayName.isEmpty, "\(opt.rawValue) has empty displayName")
        }
    }

    func testAllSortOptionsHaveAtLeastOneQueryItem() {
        for opt in InventorySortOption.allCases {
            XCTAssertFalse(opt.queryItems.isEmpty, "\(opt.rawValue) has no query items")
        }
    }

    // MARK: - InventoryAdvancedFilter

    func testAdvancedFilter_isEmpty_default() {
        let f = InventoryAdvancedFilter()
        XCTAssertTrue(f.isEmpty)
    }

    func testAdvancedFilter_isEmpty_withManufacturer() {
        let f = InventoryAdvancedFilter(manufacturer: "Apple")
        XCTAssertFalse(f.isEmpty)
    }

    func testAdvancedFilter_isEmpty_hideOutOfStock() {
        let f = InventoryAdvancedFilter(hideOutOfStock: true)
        XCTAssertFalse(f.isEmpty)
    }

    func testAdvancedFilter_isEmpty_lowStockOnly() {
        let f = InventoryAdvancedFilter(lowStockOnly: true)
        XCTAssertFalse(f.isEmpty)
    }

    func testAdvancedFilter_queryItems_manufacturer() {
        let f = InventoryAdvancedFilter(manufacturer: "Samsung")
        let items = f.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "manufacturer" && $0.value == "Samsung" }))
    }

    func testAdvancedFilter_queryItems_priceBounds() {
        let f = InventoryAdvancedFilter(minPriceCents: 100, maxPriceCents: 9999)
        let items = f.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "min_price_cents" && $0.value == "100" }))
        XCTAssertTrue(items.contains(where: { $0.name == "max_price_cents" && $0.value == "9999" }))
    }

    func testAdvancedFilter_queryItems_empty_producesNoItems() {
        let f = InventoryAdvancedFilter()
        XCTAssertTrue(f.queryItems.isEmpty)
    }

    func testAdvancedFilter_queryItems_toggles() {
        let f = InventoryAdvancedFilter(hideOutOfStock: true, reorderableOnly: true)
        let items = f.queryItems
        XCTAssertTrue(items.contains(where: { $0.name == "hide_out_of_stock" && $0.value == "true" }))
        XCTAssertTrue(items.contains(where: { $0.name == "reorderable_only" && $0.value == "true" }))
    }

    func testAdvancedFilter_hashable_equality() {
        let f1 = InventoryAdvancedFilter(manufacturer: "LG", hideOutOfStock: true)
        let f2 = InventoryAdvancedFilter(manufacturer: "LG", hideOutOfStock: true)
        XCTAssertEqual(f1, f2)
    }

    func testAdvancedFilter_hashable_inequality() {
        let f1 = InventoryAdvancedFilter(manufacturer: "LG")
        let f2 = InventoryAdvancedFilter(manufacturer: "Sony")
        XCTAssertNotEqual(f1, f2)
    }

    // MARK: - InventoryListViewModel sort/filter

    func testViewModelDefaultSort_isNameAsc() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        let sort = await vm.sort
        XCTAssertEqual(sort, .nameAsc)
    }

    func testViewModelApplySort_updatesSort() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        await vm.applySort(.stockDesc)
        let sort = await vm.sort
        XCTAssertEqual(sort, .stockDesc)
    }

    func testViewModelApplyAdvanced_updatesAdvanced() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        let newFilter = InventoryAdvancedFilter(manufacturer: "Canon", hideOutOfStock: true)
        await vm.applyAdvanced(newFilter)
        let advanced = await vm.advanced
        XCTAssertEqual(advanced, newFilter)
    }

    func testViewModelHasActiveAdvancedFilters_falseByDefault() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        let hasFilters = await vm.hasActiveAdvancedFilters
        XCTAssertFalse(hasFilters)
    }

    func testViewModelHasActiveAdvancedFilters_trueWhenSet() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        await vm.applyAdvanced(InventoryAdvancedFilter(lowStockOnly: true))
        let hasFilters = await vm.hasActiveAdvancedFilters
        XCTAssertTrue(hasFilters)
    }

    func testViewModelLoad_callsListAdvanced() async {
        let repo = MockInventoryRepo()
        let vm = await InventoryListViewModel(repo: repo)
        await vm.load()
        let callCount = await repo.listAdvancedCallCount
        XCTAssertEqual(callCount, 1)
    }
}

// MARK: - MockInventoryRepo

private actor MockInventoryRepo: InventoryRepository {
    private(set) var listAdvancedCallCount: Int = 0
    private(set) var lastSort: InventorySortOption?
    private(set) var lastAdvanced: InventoryAdvancedFilter?

    func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] {
        return []
    }

    func listAdvanced(
        filter: InventoryFilter,
        sort: InventorySortOption,
        advanced: InventoryAdvancedFilter,
        keyword: String?
    ) async throws -> [InventoryListItem] {
        listAdvancedCallCount += 1
        lastSort = sort
        lastAdvanced = advanced
        return []
    }
}
