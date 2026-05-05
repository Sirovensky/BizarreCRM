import XCTest
import Networking
@testable import Pos

/// §16.5 — Tests for `PosTransactionMapper`.
///
/// Verifies the cart → `PosTransactionRequest` mapping without any network
/// calls. All tests run on `@MainActor` because `Cart` is `@MainActor`.
@MainActor
final class PosTransactionMapperTests: XCTestCase {

    // MARK: - Happy path

    func test_singleInventoryItem_mapsCorrectly() throws {
        let cart = makeCart(items: [
            CartItem(
                name: "Screen Repair",
                quantity: 1,
                unitPrice: 89.99,
                inventoryItemId: 42
            )
        ])
        let req = try PosTransactionMapper.request(
            from: cart,
            paymentMethod: "cash",
            paymentAmountCents: 8999,
            idempotencyKey: "test-key-1"
        )
        XCTAssertEqual(req.items.count, 1)
        XCTAssertEqual(req.items[0].inventoryItemId, 42)
        XCTAssertEqual(req.items[0].quantity, 1)
        XCTAssertNil(req.items[0].lineDiscount)
        XCTAssertEqual(req.paymentMethod, "cash")
        XCTAssertEqual(req.paymentAmount, 89.99, accuracy: 0.001)
        XCTAssertEqual(req.idempotencyKey, "test-key-1")
        XCTAssertNil(req.customerId)
        XCTAssertNil(req.discount)
        XCTAssertNil(req.tip)
    }

    func test_multipleItems_allMapped() throws {
        let cart = makeCart(items: [
            CartItem(name: "A", quantity: 2, unitPrice: 10.00, inventoryItemId: 1),
            CartItem(name: "B", quantity: 1, unitPrice: 5.00, inventoryItemId: 2),
        ])
        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 2500,
            idempotencyKey: "key-2"
        )
        XCTAssertEqual(req.items.count, 2)
        XCTAssertEqual(req.items[0].inventoryItemId, 1)
        XCTAssertEqual(req.items[0].quantity, 2)
        XCTAssertEqual(req.items[1].inventoryItemId, 2)
        XCTAssertEqual(req.items[1].quantity, 1)
    }

    // MARK: - Line discount

    func test_lineDiscount_convertedToDollars() throws {
        let item = CartItem(name: "Lens", quantity: 1, unitPrice: 50.00, inventoryItemId: 7,
                            discountCents: 500)
        let cart = makeCart(items: [item])
        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 4500,
            idempotencyKey: "key-3"
        )
        XCTAssertNotNil(req.items[0].lineDiscount)
        XCTAssertEqual(req.items[0].lineDiscount!, 5.00, accuracy: 0.001)
    }

    func test_zeroDiscount_nilInRequest() throws {
        let item = CartItem(name: "Case", quantity: 1, unitPrice: 20.00, inventoryItemId: 8,
                            discountCents: 0)
        let cart = makeCart(items: [item])
        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 2000,
            idempotencyKey: "key-4"
        )
        XCTAssertNil(req.items[0].lineDiscount)
    }

    // MARK: - Cart-level discount + tip

    func test_cartDiscount_convertedToDollars() throws {
        let cart = makeCart(items: [
            CartItem(name: "X", quantity: 1, unitPrice: 100.00, inventoryItemId: 9)
        ])
        cart.setCartDiscount(cents: 1000)   // $10 off

        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 9000,
            idempotencyKey: "key-5"
        )
        XCTAssertNotNil(req.discount)
        XCTAssertEqual(req.discount!, 10.00, accuracy: 0.001)
    }

    func test_tip_convertedToDollars() throws {
        let cart = makeCart(items: [
            CartItem(name: "Y", quantity: 1, unitPrice: 50.00, inventoryItemId: 10)
        ])
        cart.setTip(cents: 500)   // $5 tip

        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 5500,
            idempotencyKey: "key-6"
        )
        XCTAssertNotNil(req.tip)
        XCTAssertEqual(req.tip!, 5.00, accuracy: 0.001)
    }

    // MARK: - Customer

    func test_customer_id_attached() throws {
        let cart = makeCart(items: [
            CartItem(name: "Z", quantity: 1, unitPrice: 10.00, inventoryItemId: 11)
        ])
        cart.attach(customer: PosCustomer(id: 77, displayName: "Alice"))

        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 1000,
            idempotencyKey: "key-7"
        )
        XCTAssertEqual(req.customerId, 77)
    }

    func test_noCustomer_nilId() throws {
        let cart = makeCart(items: [
            CartItem(name: "W", quantity: 1, unitPrice: 10.00, inventoryItemId: 12)
        ])
        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 1000,
            idempotencyKey: "key-8"
        )
        XCTAssertNil(req.customerId)
    }

    // MARK: - Custom line error

    func test_customLine_throws() {
        let cart = makeCart(items: [
            CartItem(name: "Custom Repair", quantity: 1, unitPrice: 40.00, inventoryItemId: nil)
        ])
        XCTAssertThrowsError(
            try PosTransactionMapper.request(
                from: cart, paymentMethod: "cash", paymentAmountCents: 4000,
                idempotencyKey: "key-9"
            )
        ) { error in
            guard case PosTransactionMapper.MapperError.customLineNotSupported(let msg) = error else {
                XCTFail("Expected customLineNotSupported, got \(error)")
                return
            }
            XCTAssertTrue(msg.contains("Custom Repair"), "Error message must name the item")
        }
    }

    func test_mixedCartWithCustomLine_throws() {
        let cart = makeCart(items: [
            CartItem(name: "Catalogued Item", quantity: 1, unitPrice: 10.00, inventoryItemId: 1),
            CartItem(name: "Custom", quantity: 1, unitPrice: 5.00, inventoryItemId: nil),
        ])
        XCTAssertThrowsError(
            try PosTransactionMapper.request(
                from: cart, paymentMethod: "cash", paymentAmountCents: 1500,
                idempotencyKey: "key-10"
            )
        )
    }

    // MARK: - Idempotency key forwarded

    func test_idempotencyKey_forwarded() throws {
        let cart = makeCart(items: [
            CartItem(name: "A", quantity: 1, unitPrice: 5.00, inventoryItemId: 1)
        ])
        let key = UUID().uuidString
        let req = try PosTransactionMapper.request(
            from: cart, paymentMethod: "cash", paymentAmountCents: 500,
            idempotencyKey: key
        )
        XCTAssertEqual(req.idempotencyKey, key)
    }

    // MARK: - Helpers

    private func makeCart(items: [CartItem]) -> Cart {
        Cart(items: items)
    }
}

// MARK: - CartItem convenience init for tests

private extension CartItem {
    init(
        name: String,
        quantity: Int,
        unitPrice: Double,
        inventoryItemId: Int64?,
        discountCents: Int = 0
    ) {
        self.init(
            inventoryItemId: inventoryItemId,
            name: name,
            quantity: quantity,
            unitPrice: Decimal(unitPrice),
            discountCents: discountCents
        )
    }
}
