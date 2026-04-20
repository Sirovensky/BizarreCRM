import XCTest
@testable import Pos

/// §16.4 customer-attach behaviour on `Cart`. Every test isolates a single
/// state transition so a regression here points at the exact method, not
/// the whole surface. The `Cart` is `@MainActor`, so the suite is too.
@MainActor
final class PosCustomerAttachTests: XCTestCase {

    // MARK: - PosCustomer value type

    func test_walkIn_sentinel_hasNilIdAndIsWalkInTrue() {
        let walkIn = PosCustomer.walkIn
        XCTAssertNil(walkIn.id)
        XCTAssertTrue(walkIn.isWalkIn)
        XCTAssertEqual(walkIn.displayName, "Walk-in")
    }

    func test_walkIn_initials_fallbackToW() {
        XCTAssertEqual(PosCustomer.walkIn.initials, "W")
    }

    func test_realCustomer_isWalkInFalse_andInitialsFromName() {
        let c = PosCustomer(id: 42, displayName: "Ada Lovelace", email: "ada@example.com")
        XCTAssertFalse(c.isWalkIn)
        XCTAssertEqual(c.initials, "AL")
        XCTAssertEqual(c.id, 42)
        XCTAssertEqual(c.email, "ada@example.com")
    }

    func test_realCustomer_singleNameInitialsOk() {
        let c = PosCustomer(id: 1, displayName: "Madonna")
        XCTAssertEqual(c.initials, "M")
    }

    func test_realCustomer_blankName_initialsFallback() {
        let c = PosCustomer(id: 1, displayName: "")
        XCTAssertEqual(c.initials, "?")
    }

    // MARK: - Cart transitions

    func test_newCart_hasNoCustomer() {
        let cart = Cart()
        XCTAssertNil(cart.customer)
        XCTAssertFalse(cart.hasCustomer)
    }

    func test_attachWalkIn_setsIsWalkInTrueAndHasCustomer() {
        let cart = Cart()
        cart.attach(customer: .walkIn)
        XCTAssertNotNil(cart.customer)
        XCTAssertTrue(cart.customer?.isWalkIn ?? false)
        XCTAssertNil(cart.customer?.id)
        XCTAssertTrue(cart.hasCustomer)
    }

    func test_attachRealCustomer_setsIdAndDisplayName() {
        let cart = Cart()
        let ada = PosCustomer(id: 7, displayName: "Ada Lovelace", email: "ada@example.com", phone: "555-1212")
        cart.attach(customer: ada)
        XCTAssertEqual(cart.customer?.id, 7)
        XCTAssertEqual(cart.customer?.displayName, "Ada Lovelace")
        XCTAssertEqual(cart.customer?.email, "ada@example.com")
        XCTAssertEqual(cart.customer?.phone, "555-1212")
        XCTAssertFalse(cart.customer?.isWalkIn ?? true)
    }

    func test_attach_twice_lastWriteWins() {
        let cart = Cart()
        cart.attach(customer: .walkIn)
        cart.attach(customer: PosCustomer(id: 3, displayName: "Grace Hopper"))
        XCTAssertEqual(cart.customer?.id, 3)
        XCTAssertEqual(cart.customer?.displayName, "Grace Hopper")
    }

    func test_detachCustomer_clearsCustomerButKeepsItems() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: Decimal(string: "9.99")!))
        cart.attach(customer: PosCustomer(id: 9, displayName: "Linus"))
        XCTAssertEqual(cart.lineCount, 1)
        XCTAssertNotNil(cart.customer)

        cart.detachCustomer()
        XCTAssertNil(cart.customer)
        XCTAssertFalse(cart.hasCustomer)
        XCTAssertEqual(cart.lineCount, 1, "detach must NOT drop line items")
    }

    func test_clear_clearsCustomerAndItems() {
        let cart = Cart()
        cart.add(CartItem(name: "A", unitPrice: 1))
        cart.attach(customer: PosCustomer(id: 1, displayName: "Alan Turing"))
        cart.clear()
        XCTAssertNil(cart.customer)
        XCTAssertFalse(cart.hasCustomer)
        XCTAssertTrue(cart.isEmpty)
    }

    func test_init_withCustomer_seeds() {
        let cart = Cart(customer: .walkIn)
        XCTAssertTrue(cart.hasCustomer)
        XCTAssertTrue(cart.customer?.isWalkIn ?? false)
    }
}
