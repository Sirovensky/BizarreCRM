import XCTest
@testable import Pos

@MainActor
final class CFDBridgeTests: XCTestCase {

    private func makeCart(items: [CartItem] = []) -> Cart {
        Cart(items: items)
    }

    private func makeItem(name: String, unitPrice: Decimal, quantity: Int = 1) -> CartItem {
        CartItem(name: name, quantity: quantity, unitPrice: unitPrice)
    }

    // MARK: - Initial state

    func test_initialStateIsIdle() {
        let bridge = CFDBridge()
        XCTAssertFalse(bridge.isActive)
        XCTAssertTrue(bridge.items.isEmpty)
        XCTAssertEqual(bridge.totalCents, 0)
    }

    // MARK: - update(from:)

    func test_updateWithSingleItem() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [makeItem(name: "Widget", unitPrice: 9.99)])

        bridge.update(from: cart)

        XCTAssertTrue(bridge.isActive)
        XCTAssertEqual(bridge.items.count, 1)
        XCTAssertEqual(bridge.items[0].name, "Widget")
        XCTAssertEqual(bridge.items[0].quantity, 1)
    }

    func test_updateWithMultipleItems() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [
            makeItem(name: "Screen Repair", unitPrice: 129.99),
            makeItem(name: "Protector",     unitPrice: 14.99, quantity: 2),
        ])
        bridge.update(from: cart)

        XCTAssertEqual(bridge.items.count, 2)
    }

    func test_totalsForwardedCorrectly() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [
            CartItem(name: "Item A", quantity: 2, unitPrice: Decimal(5))   // 2 × $5 = $10
        ])
        bridge.update(from: cart)

        XCTAssertEqual(bridge.subtotalCents, 1000) // $10.00
        XCTAssertEqual(bridge.totalCents,    1000)
    }

    func test_updateReplacesOldSnapshot() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [makeItem(name: "First", unitPrice: 1.00)])
        bridge.update(from: cart)

        let cart2 = makeCart(items: [
            makeItem(name: "Second", unitPrice: 2.00),
            makeItem(name: "Third",  unitPrice: 3.00),
        ])
        bridge.update(from: cart2)

        XCTAssertEqual(bridge.items.count, 2)
        XCTAssertFalse(bridge.items.map { $0.name }.contains("First"))
    }

    // MARK: - clear()

    func test_clearResetsToIdle() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [makeItem(name: "X", unitPrice: 1.00)])
        bridge.update(from: cart)
        XCTAssertTrue(bridge.isActive)

        bridge.clear()

        XCTAssertFalse(bridge.isActive)
        XCTAssertTrue(bridge.items.isEmpty)
        XCTAssertEqual(bridge.totalCents, 0)
        XCTAssertEqual(bridge.subtotalCents, 0)
        XCTAssertEqual(bridge.taxCents, 0)
        XCTAssertEqual(bridge.tipCents, 0)
    }

    // MARK: - Empty cart

    func test_updateWithEmptyCartIsIdle() {
        let bridge = CFDBridge()
        bridge.update(from: makeCart())
        XCTAssertFalse(bridge.isActive)
    }

    // MARK: - CFDCartLine properties

    func test_cartLineIdMatchesCartItemId() {
        let bridge = CFDBridge()
        let item = makeItem(name: "Keyed", unitPrice: 5.00)
        let cart = makeCart(items: [item])
        bridge.update(from: cart)

        XCTAssertEqual(bridge.items[0].id, item.id)
    }

    func test_cartLineTotalReflectsLineSubtotal() {
        let bridge = CFDBridge()
        let item = CartItem(name: "Bulk", quantity: 3, unitPrice: Decimal(10)) // 3 × $10 = $30
        let cart = makeCart(items: [item])
        bridge.update(from: cart)

        XCTAssertEqual(bridge.items[0].lineTotalCents, 3000)
    }

    // MARK: - Cart with tax & tip forwarded

    func test_taxAndTipForwarded() {
        let bridge = CFDBridge()
        let cart = makeCart(items: [
            CartItem(name: "Service", quantity: 1, unitPrice: Decimal(100), taxRate: Decimal(0.08))
        ])
        cart.setTip(cents: 1500)
        bridge.update(from: cart)

        XCTAssertEqual(bridge.taxCents, 800)    // 8% of $100
        XCTAssertEqual(bridge.tipCents, 1500)
        // totalCents = subtotal(10000) + tax(800) + tip(1500) = 12300
        XCTAssertEqual(bridge.totalCents, 12300)
    }
}
