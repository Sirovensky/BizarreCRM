import XCTest
@testable import Pos

/// §16.7 — Tests for `PosReceiptSummaryView` payload correctness.
///
/// The view itself is UIKit-only, but the payload it renders is pure logic
/// that can be tested on any host. These tests verify that the
/// `PosReceiptRenderer.Payload` snapshot produced by `PosReceiptPayloadBuilder`
/// has the shape that `PosReceiptSummaryView` expects to render.
@MainActor
final class PosReceiptSummaryViewModelTests: XCTestCase {

    // MARK: - Payload construction

    func test_payload_hasCorrectLineCount() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.lines.count, 2)
    }

    func test_payload_lineNames_match() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.lines[0].name, "Screen Repair")
        XCTAssertEqual(payload.lines[1].name, "Screen Protector")
    }

    func test_payload_lineQuantities_match() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.lines[0].quantity, 1)
        XCTAssertEqual(payload.lines[1].quantity, 2)
    }

    func test_payload_totalCents_matches_cart() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.totalCents, cart.totalCents)
    }

    func test_payload_subtotalCents_matches_cart() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.subtotalCents, cart.subtotalCents)
    }

    func test_payload_customerName_set_whenAttached() {
        let cart = makeCartWithItems()
        cart.attach(customer: PosCustomer(id: 1, displayName: "Jane Smith"))
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.customerName, "Jane Smith")
    }

    func test_payload_customerName_nil_whenNoCustomer() {
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertNil(payload.customerName)
    }

    func test_payload_date_isRecent() {
        let before = Date().addingTimeInterval(-5)
        let cart = makeCartWithItems()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        let after = Date().addingTimeInterval(5)
        XCTAssertTrue(payload.date >= before && payload.date <= after)
    }

    // MARK: - Tax in payload

    func test_payload_taxCents_whenTaxed() {
        let item = CartItem(
            inventoryItemId: 1,
            name: "Taxed Item",
            quantity: 1,
            unitPrice: 100,
            taxRate: Decimal(0.08)
        )
        let cart = Cart(items: [item])
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertGreaterThan(payload.taxCents, 0)
    }

    // MARK: - Payload Equatable

    func test_payloads_equalForSameCart() {
        let date = Date(timeIntervalSince1970: 0)
        let cart = makeCartWithItems()
        let p1 = PosReceiptPayloadBuilder.build(cart: cart, date: date)
        let p2 = PosReceiptPayloadBuilder.build(cart: cart, date: date)
        XCTAssertEqual(p1, p2)
    }

    // MARK: - Line discount in payload

    func test_payload_lineDiscountCents_reflected() {
        let item = CartItem(
            inventoryItemId: 1,
            name: "Discounted Item",
            quantity: 1,
            unitPrice: 50,
            discountCents: 500
        )
        let cart = Cart(items: [item])
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.lines[0].discountCents, 500)
    }

    // MARK: - Helpers

    private func makeCartWithItems() -> Cart {
        Cart(items: [
            CartItem(
                inventoryItemId: 1,
                name: "Screen Repair",
                quantity: 1,
                unitPrice: 89.99
            ),
            CartItem(
                inventoryItemId: 2,
                name: "Screen Protector",
                quantity: 2,
                unitPrice: 12.99
            ),
        ])
    }
}
