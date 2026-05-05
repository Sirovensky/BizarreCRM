import XCTest
@testable import Pos

/// Tests for `PosReceiptPayloadBuilder`.
///
/// Verifies that the builder maps `Cart` state — including applied tenders,
/// discount, tip, fees, and the method-rail payment row — into the receipt
/// payload correctly. No networking is involved.
@MainActor
final class PosReceiptPayloadBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeCart(priceCents: Int = 1000) -> Cart {
        let cart = Cart()
        let price = Decimal(priceCents) / 100
        cart.add(CartItem(inventoryItemId: 1, name: "Widget", unitPrice: price))
        return cart
    }

    // MARK: - Lines mapping

    func test_build_mapsCartItemsToLines() {
        let cart = Cart()
        cart.add(CartItem(inventoryItemId: 1, name: "Screen", sku: "SCR-01", quantity: 2,
                          unitPrice: Decimal(string: "25.00")!))
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.lines.count, 1)
        let line = payload.lines[0]
        XCTAssertEqual(line.name, "Screen")
        XCTAssertEqual(line.sku, "SCR-01")
        XCTAssertEqual(line.quantity, 2)
        XCTAssertEqual(line.unitPriceCents, 2500)
        XCTAssertEqual(line.lineTotalCents, 5000)
    }

    // MARK: - Customer name

    func test_build_includesCustomerName() {
        let cart = makeCart()
        cart.attach(customer: PosCustomer(id: 1, displayName: "Alice Tester"))
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.customerName, "Alice Tester")
    }

    func test_build_noCustomer_nilName() {
        let cart = makeCart()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertNil(payload.customerName)
    }

    // MARK: - Totals

    func test_build_subtotalAndTax_reflected() {
        let cart = Cart()
        cart.add(CartItem(
            inventoryItemId: 1,
            name: "A",
            quantity: 1,
            unitPrice: Decimal(string: "10.00")!,
            taxRate: Decimal(string: "0.10")
        ))
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.subtotalCents, 1000)
        XCTAssertEqual(payload.taxCents, 100)
        XCTAssertEqual(payload.totalCents, 1100)
    }

    func test_build_discount_reflected() {
        let cart = makeCart(priceCents: 2000)
        cart.setCartDiscount(cents: 500)
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.discountCents, 500)
    }

    func test_build_tip_reflected() {
        let cart = makeCart(priceCents: 1000)
        cart.setTip(cents: 200)
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.tipCents, 200)
    }

    func test_build_fees_reflected() {
        let cart = makeCart(priceCents: 1000)
        cart.setFees(cents: 300, label: "Delivery")
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.feesCents, 300)
    }

    // MARK: - Tender rows

    func test_build_cashMethod_singleTenderRow() {
        let cart = makeCart(priceCents: 1500)
        let payload = PosReceiptPayloadBuilder.build(
            cart: cart,
            methodLabel: "Cash",
            methodAmountCents: 2000
        )
        XCTAssertEqual(payload.tenders.count, 1)
        XCTAssertEqual(payload.tenders[0].method, "Cash")
        XCTAssertEqual(payload.tenders[0].amountCents, 2000)
    }

    func test_build_appliedTenders_listFirst_thenMethodRail() {
        let cart = makeCart(priceCents: 5000)
        cart.apply(tender: AppliedTender(
            kind: .giftCard,
            amountCents: 2000,
            label: "Gift card ••••1234"
        ))
        let payload = PosReceiptPayloadBuilder.build(
            cart: cart,
            methodLabel: "Cash",
            methodAmountCents: 3000
        )
        XCTAssertEqual(payload.tenders.count, 2)
        XCTAssertEqual(payload.tenders[0].method, "Gift card ••••1234")
        XCTAssertEqual(payload.tenders[0].amountCents, 2000)
        XCTAssertEqual(payload.tenders[1].method, "Cash")
        XCTAssertEqual(payload.tenders[1].amountCents, 3000)
    }

    func test_build_fullyTenderedByGiftCards_noExtraRow() {
        let cart = makeCart(priceCents: 3000)
        cart.apply(tender: AppliedTender(kind: .giftCard, amountCents: 3000, label: "Gift card"))
        // No methodLabel / methodAmountCents — fully covered by gift card.
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertEqual(payload.tenders.count, 1)
        XCTAssertEqual(payload.tenders[0].method, "Gift card")
    }

    func test_build_noTenders_noMethod_fallbackRow() {
        // Edge case: no applied tenders and no method passed.
        // The builder must not emit an empty tenders list.
        let cart = makeCart(priceCents: 1000)
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertFalse(payload.tenders.isEmpty, "Receipt must always have at least one tender row")
    }

    // MARK: - Order number pass-through

    func test_build_orderNumber_passedThrough() {
        let cart = makeCart()
        let payload = PosReceiptPayloadBuilder.build(cart: cart, orderNumber: "INV-2026-001")
        XCTAssertEqual(payload.orderNumber, "INV-2026-001")
    }

    func test_build_noOrderNumber_nil() {
        let cart = makeCart()
        let payload = PosReceiptPayloadBuilder.build(cart: cart)
        XCTAssertNil(payload.orderNumber)
    }
}
