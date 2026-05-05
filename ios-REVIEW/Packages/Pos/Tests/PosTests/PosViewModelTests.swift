import XCTest
@testable import Pos

// MARK: - PosViewModelTests
//
// §16.1 / §16.2 / §16.4 unit tests for PosViewModel pure logic.
// No network calls — all async paths are gated on api == nil which
// returns early, so tests are synchronous-safe on MainActor.

@MainActor
final class PosViewModelTests: XCTestCase {

    // MARK: - Permission gate (§16.1)

    func test_permission_defaultPreviewRole_canAccessPos() {
        let vm = PosViewModel(api: nil, userRole: .preview)
        XCTAssertTrue(vm.userRole.canAccessPos)
    }

    func test_permission_loadingRole_cannotAccessPos() {
        let vm = PosViewModel(api: nil, userRole: .loading)
        XCTAssertFalse(vm.userRole.canAccessPos)
    }

    func test_permission_restrictedRole_cannotAccessPos() {
        let role = PosUserRole(canAccessPos: false, displayName: "Staff")
        let vm = PosViewModel(api: nil, userRole: role)
        XCTAssertFalse(vm.userRole.canAccessPos)
    }

    // MARK: - Favorites (§16.2)

    func test_toggleFavorite_addsItem() {
        let vm = PosViewModel(api: nil)
        XCTAssertFalse(vm.isFavorite(itemId: 42))
        vm.toggleFavorite(itemId: 42)
        XCTAssertTrue(vm.isFavorite(itemId: 42))
    }

    func test_toggleFavorite_removesItem() {
        let vm = PosViewModel(api: nil)
        vm.toggleFavorite(itemId: 99)
        XCTAssertTrue(vm.isFavorite(itemId: 99))
        vm.toggleFavorite(itemId: 99)
        XCTAssertFalse(vm.isFavorite(itemId: 99))
    }

    func test_toggleFavorite_doesNotAffectOthers() {
        let vm = PosViewModel(api: nil)
        vm.toggleFavorite(itemId: 1)
        XCTAssertFalse(vm.isFavorite(itemId: 2))
    }

    // MARK: - Recently sold (§16.2)

    func test_recordSale_populatesRecentlySold() {
        let vm = PosViewModel(api: nil)
        vm.recordSale(itemIds: [10, 20, 30])
        XCTAssertEqual(vm.recentlySoldIds.prefix(3), [10, 20, 30])
    }

    func test_recordSale_floatsNewItemsToTop() {
        let vm = PosViewModel(api: nil)
        vm.recordSale(itemIds: [1, 2, 3])
        vm.recordSale(itemIds: [4])
        XCTAssertEqual(vm.recentlySoldIds.first, 4)
    }

    func test_recordSale_capsAt10() {
        let vm = PosViewModel(api: nil)
        vm.recordSale(itemIds: Array(1...15))
        XCTAssertLessThanOrEqual(vm.recentlySoldIds.count, 10)
    }

    func test_recordSale_deduplicates() {
        let vm = PosViewModel(api: nil)
        vm.recordSale(itemIds: [1, 2])
        vm.recordSale(itemIds: [1])
        let uniqueIds = Set(vm.recentlySoldIds)
        XCTAssertEqual(vm.recentlySoldIds.count, uniqueIds.count)
    }

    // MARK: - Loyalty points preview (§16.4)

    func test_loyaltyPreview_nilWhenNoRate() {
        let vm = PosViewModel(api: nil)
        // No customer context loaded — rate is nil.
        XCTAssertNil(vm.loyaltyPointsPreview(cartTotalCents: 1000))
    }

    func test_loyaltyPreview_computesCorrectly() {
        let vm = PosViewModel(api: nil)
        // Manually inject context with 1.5 pts/dollar.
        vm._injectCustomerContextForTesting(PosCustomerContext(
            loyaltyPointsBalance: 100,
            loyaltyPointsPerDollar: 1.5
        ))
        // $10.00 × 1.5 = 15 points.
        XCTAssertEqual(vm.loyaltyPointsPreview(cartTotalCents: 1000), 15)
    }

    func test_loyaltyPreview_roundsToNearest() {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(loyaltyPointsPerDollar: 1.0))
        // $0.50 × 1.0 = 0.5 → rounds to 1.
        XCTAssertEqual(vm.loyaltyPointsPreview(cartTotalCents: 50), 1)
    }

    func test_loyaltyPreview_zeroCartTotal() {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(loyaltyPointsPerDollar: 2.0))
        XCTAssertEqual(vm.loyaltyPointsPreview(cartTotalCents: 0), 0)
    }

    // MARK: - Tax exemption (§16.4)

    func test_applyTaxExemption_setsAllTaxRatesNil() {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(isTaxExempt: true))

        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 10, taxRate: Decimal(0.08)))
        cart.add(CartItem(name: "Gadget", unitPrice: 20, taxRate: Decimal(0.10)))

        let changed = vm.applyTaxExemptionIfNeeded(to: cart)

        XCTAssertTrue(changed)
        XCTAssertTrue(cart.items.allSatisfy { $0.taxRate == nil })
    }

    func test_applyTaxExemption_noopWhenNotExempt() {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(isTaxExempt: false))

        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 10, taxRate: Decimal(0.08)))

        let changed = vm.applyTaxExemptionIfNeeded(to: cart)

        XCTAssertFalse(changed)
        XCTAssertEqual(cart.items.first?.taxRate, Decimal(0.08))
    }

    // MARK: - Client filters (§16.2 Search filters)

    func test_applyClientFilters_inStockOnly_filtersZeroStock() {
        let vm = PosViewModel(api: nil)
        vm.catalogFilter.inStockOnly = true

        let items: [InventoryListItemStub] = [
            .init(id: 1, inStock: 0),
            .init(id: 2, inStock: 5),
            .init(id: 3, inStock: nil)
        ]
        let result = vm.applyClientFilters(to: items.map(\.asInventoryListItem))
        // inStock=0 filtered out; nil (service) kept.
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == 2 })
        XCTAssertTrue(result.contains { $0.id == 3 })
    }

    func test_applyClientFilters_priceRange_filtersOutOfRange() {
        let vm = PosViewModel(api: nil)
        vm.catalogFilter.minPriceCents = 500
        vm.catalogFilter.maxPriceCents = 1000

        let items: [InventoryListItemStub] = [
            .init(id: 1, priceCents: 300),
            .init(id: 2, priceCents: 750),
            .init(id: 3, priceCents: 1500)
        ]
        let result = vm.applyClientFilters(to: items.map(\.asInventoryListItem))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 2)
    }

    func test_applyClientFilters_empty_returnsAll() {
        let vm = PosViewModel(api: nil)
        // Default filter: nothing active.
        let items: [InventoryListItemStub] = [
            .init(id: 1), .init(id: 2), .init(id: 3)
        ]
        let result = vm.applyClientFilters(to: items.map(\.asInventoryListItem))
        XCTAssertEqual(result.count, 3)
    }

    // MARK: - Sorted (favorites float first)

    func test_sorted_favoritesFloatFirst() {
        let vm = PosViewModel(api: nil)
        vm.toggleFavorite(itemId: 3)

        let items: [InventoryListItemStub] = [
            .init(id: 1, name: "Apple"),
            .init(id: 2, name: "Banana"),
            .init(id: 3, name: "Cranberry")  // favorite
        ]
        let result = vm.sorted(items.map(\.asInventoryListItem))
        XCTAssertEqual(result.first?.id, 3)
    }

    func test_sorted_alphabeticalAmongNonFavorites() {
        let vm = PosViewModel(api: nil)

        let items: [InventoryListItemStub] = [
            .init(id: 2, name: "Banana"),
            .init(id: 1, name: "Apple"),
            .init(id: 3, name: "Cherry")
        ]
        let result = vm.sorted(items.map(\.asInventoryListItem))
        XCTAssertEqual(result.map(\.id), [1, 2, 3])
    }

    // MARK: - Customer context (§16.4)

    func test_customerContext_noApi_resetsToEmpty() async {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(isTaxExempt: true))
        await vm.loadCustomerContext(customerId: nil)
        XCTAssertEqual(vm.customerContext, .empty)
    }

    func test_customerContext_nilCustomerId_resetsToEmpty() async {
        let vm = PosViewModel(api: nil)
        vm._injectCustomerContextForTesting(PosCustomerContext(loyaltyPointsBalance: 100))
        await vm.loadCustomerContext(customerId: nil)
        XCTAssertEqual(vm.customerContext, .empty)
    }

    func test_customerContext_zeroCustomerId_resetsToEmpty() async {
        let vm = PosViewModel(api: nil)
        await vm.loadCustomerContext(customerId: 0)
        XCTAssertEqual(vm.customerContext, .empty)
    }
}

// MARK: - InventoryListItemStub (test helper)

private struct InventoryListItemStub {
    let id: Int64
    var name: String = "Item"
    var inStock: Int? = nil
    var priceCents: Int? = nil

    var asInventoryListItem: InventoryListItem {
        // InventoryListItem is Decodable only; build via JSON round-trip.
        var dict: [String: Any] = [
            "id": id,
            "name": name
        ]
        if let stock = inStock { dict["in_stock"] = stock }
        if let cents = priceCents {
            // priceCents is derived from retailPrice (Double).
            dict["retail_price"] = Double(cents) / 100.0
        }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(InventoryListItem.self, from: data)
    }
}
