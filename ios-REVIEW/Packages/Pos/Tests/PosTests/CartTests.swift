import XCTest
@testable import Pos

@MainActor
final class CartTests: XCTestCase {

    // Starting state: empty cart, all totals zero.
    func test_newCart_isEmpty() {
        let cart = Cart()
        XCTAssertTrue(cart.isEmpty)
        XCTAssertEqual(cart.subtotalCents, 0)
        XCTAssertEqual(cart.taxCents, 0)
        XCTAssertEqual(cart.totalCents, 0)
        XCTAssertEqual(cart.lineCount, 0)
        XCTAssertEqual(cart.itemQuantity, 0)
    }

    func test_add_appendsRow() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: Decimal(string: "9.99")!))
        XCTAssertEqual(cart.lineCount, 1)
        XCTAssertEqual(cart.items.first?.name, "Widget")
        XCTAssertFalse(cart.isEmpty)
    }

    func test_add_doesNotAutoMergeSameInventoryItem() {
        let cart = Cart()
        let a = CartItem(inventoryItemId: 42, name: "Case", unitPrice: Decimal(string: "5.00")!)
        let b = CartItem(inventoryItemId: 42, name: "Case", unitPrice: Decimal(string: "5.00")!)
        cart.add(a)
        cart.add(b)
        XCTAssertEqual(cart.lineCount, 2)
    }

    func test_remove_dropsRow() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: 1)
        let b = CartItem(name: "B", unitPrice: 2)
        cart.add(a)
        cart.add(b)
        cart.remove(id: a.id)
        XCTAssertEqual(cart.lineCount, 1)
        XCTAssertEqual(cart.items.first?.id, b.id)
    }

    func test_remove_unknownId_isNoOp() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: 1)
        cart.add(a)
        cart.remove(id: UUID())
        XCTAssertEqual(cart.lineCount, 1)
    }

    func test_updateQuantity_replacesRowInPlaceByIdentity() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: Decimal(string: "3.00")!)
        cart.add(a)
        cart.update(id: a.id, quantity: 5)
        XCTAssertEqual(cart.items.first?.quantity, 5)
        XCTAssertEqual(cart.items.first?.id, a.id)
    }

    func test_updateQuantity_belowOne_removesRow() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: 1)
        cart.add(a)
        cart.update(id: a.id, quantity: 0)
        XCTAssertTrue(cart.isEmpty)
    }

    func test_updatePrice_storesAsDecimalDerivedFromCents() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: Decimal(string: "1.00")!)
        cart.add(a)
        cart.update(id: a.id, unitPriceCents: 499)
        XCTAssertEqual(cart.items.first?.unitPrice, Decimal(string: "4.99")!)
    }

    func test_updatePrice_clampsNegative() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: Decimal(string: "1.00")!)
        cart.add(a)
        cart.update(id: a.id, unitPriceCents: -100)
        XCTAssertEqual(cart.items.first?.unitPrice, 0)
    }

    func test_clear_empties() {
        let cart = Cart()
        cart.add(CartItem(name: "A", unitPrice: 1))
        cart.add(CartItem(name: "B", unitPrice: 2))
        cart.clear()
        XCTAssertTrue(cart.isEmpty)
    }

    // Decimal precision — the classic "Double would round 1.99 × 3 wrong"
    // regression. Must land on exactly 5.97 (597 cents).
    func test_lineSubtotal_199x3_isExactly597() {
        let line = CartItem(name: "A", quantity: 3, unitPrice: Decimal(string: "1.99")!)
        XCTAssertEqual(line.lineSubtotalCents, 597)
    }

    func test_lineSubtotal_appliesDiscount() {
        let line = CartItem(
            name: "A",
            quantity: 2,
            unitPrice: Decimal(string: "10.00")!,
            discountCents: 300
        )
        // 2 × $10 = $20 − $3 discount = $17.00 → 1700 cents
        XCTAssertEqual(line.lineSubtotalCents, 1700)
    }

    func test_updateDiscount_reflectedInSubtotal() {
        let cart = Cart()
        let a = CartItem(name: "A", unitPrice: Decimal(string: "10.00")!)
        cart.add(a)
        cart.update(id: a.id, discountCents: 250)
        XCTAssertEqual(cart.subtotalCents, 750)
    }
}
