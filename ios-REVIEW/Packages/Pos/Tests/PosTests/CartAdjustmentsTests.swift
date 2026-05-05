import XCTest
@testable import Pos
@testable import Networking

/// §16.3 — Cart adjustments unit tests.
/// Exercises discount (% vs fixed), tip math, fees persistence,
/// clear() resets, totalCents combinations, and PosHold JSON shape.
@MainActor
final class CartAdjustmentsTests: XCTestCase {

    // MARK: - Fixtures

    private func cart(subtotalCents: Int) -> Cart {
        let cart = Cart()
        let price = Decimal(subtotalCents) / 100
        cart.add(CartItem(name: "Widget", unitPrice: price))
        return cart
    }

    // MARK: - Fixed-amount discount

    func test_setCartDiscount_cents_reducesTotal() {
        let c = cart(subtotalCents: 10_000)
        c.setCartDiscount(cents: 1_000)
        // subtotal 10000 - discount 1000 + tax 0 + tip 0 + fees 0 = 9000
        XCTAssertEqual(c.effectiveDiscountCents, 1_000)
        XCTAssertEqual(c.totalCents, 9_000)
    }

    func test_setCartDiscount_cents_clearsPercent() {
        let c = cart(subtotalCents: 5_000)
        c.setCartDiscountPercent(0.10)
        c.setCartDiscount(cents: 200)
        XCTAssertNil(c.cartDiscountPercent, "Setting fixed discount must clear percent")
        XCTAssertEqual(c.cartDiscountCents, 200)
    }

    func test_setCartDiscount_negativeInput_clampsToZero() {
        let c = cart(subtotalCents: 5_000)
        c.setCartDiscount(cents: -500)
        XCTAssertEqual(c.cartDiscountCents, 0)
        XCTAssertEqual(c.effectiveDiscountCents, 0)
    }

    func test_setCartDiscount_exceedsSubtotal_clampsEffective() {
        let c = cart(subtotalCents: 1_000)
        c.setCartDiscount(cents: 5_000)   // bigger than subtotal
        // effectiveDiscountCents is clamped to subtotal
        XCTAssertEqual(c.effectiveDiscountCents, 1_000)
        // totalCents can't go below 0
        XCTAssertEqual(c.totalCents, 0)
    }

    // MARK: - Percent discount

    func test_setCartDiscountPercent_computesFromSubtotal() {
        let c = cart(subtotalCents: 20_000)
        c.setCartDiscountPercent(0.15)   // 15%
        // 20000 * 0.15 = 3000
        XCTAssertEqual(c.effectiveDiscountCents, 3_000)
        XCTAssertEqual(c.totalCents, 17_000)
        XCTAssertEqual(c.cartDiscountPercent, 0.15)
    }

    func test_setCartDiscountPercent_recomputesOnSubtotalChange() {
        let c = cart(subtotalCents: 10_000)
        c.setCartDiscountPercent(0.10)   // 10% = 1000
        // Add another item to change the subtotal
        c.add(CartItem(name: "Extra", unitPrice: Decimal(50)))  // +$50 = +5000 cents
        // effectiveDiscountCents must reflect the new subtotal
        let expected = Int((Double(c.subtotalCents) * 0.10).rounded())
        XCTAssertEqual(c.effectiveDiscountCents, expected,
            "Percent discount must re-derive from live subtotal")
    }

    func test_setCartDiscountPercent_over100_clampedTo1() {
        let c = cart(subtotalCents: 10_000)
        c.setCartDiscountPercent(1.5)    // over 100% → clamped to 100%
        XCTAssertEqual(c.cartDiscountPercent, 1.0)
        XCTAssertEqual(c.effectiveDiscountCents, 10_000)
        XCTAssertEqual(c.totalCents, 0)
    }

    func test_clearCartDiscount_zerosAndClearsPercent() {
        let c = cart(subtotalCents: 8_000)
        c.setCartDiscountPercent(0.20)
        c.clearCartDiscount()
        XCTAssertEqual(c.cartDiscountCents, 0)
        XCTAssertNil(c.cartDiscountPercent)
        XCTAssertEqual(c.effectiveDiscountCents, 0)
        XCTAssertEqual(c.totalCents, 8_000)
    }

    // MARK: - Tip

    func test_setTip_cents_addsToTotal() {
        let c = cart(subtotalCents: 5_000)
        c.setTip(cents: 750)
        // 5000 + 0 tax + 750 tip = 5750
        XCTAssertEqual(c.tipCents, 750)
        XCTAssertEqual(c.totalCents, 5_750)
    }

    func test_setTipPercent_basedOnSubtotalAfterDiscount() {
        let c = cart(subtotalCents: 10_000)
        c.setCartDiscount(cents: 2_000)  // effective subtotal 8000
        c.setTipPercent(0.20)            // 20% of 8000 = 1600
        XCTAssertEqual(c.tipCents, 1_600)
    }

    func test_setTipPercent_zeroSubtotal_produceZeroTip() {
        let c = Cart()  // empty cart → subtotal 0
        c.setTipPercent(0.15)
        XCTAssertEqual(c.tipCents, 0)
    }

    func test_setTip_negativeInput_clampsToZero() {
        let c = cart(subtotalCents: 5_000)
        c.setTip(cents: -100)
        XCTAssertEqual(c.tipCents, 0)
    }

    // MARK: - Fees

    func test_setFees_persistsAmountAndLabel() {
        let c = cart(subtotalCents: 3_000)
        c.setFees(cents: 500, label: "Delivery fee")
        XCTAssertEqual(c.feesCents, 500)
        XCTAssertEqual(c.feesLabel, "Delivery fee")
        XCTAssertEqual(c.totalCents, 3_500)
    }

    func test_setFees_nilLabel_leavesLabelNil() {
        let c = cart(subtotalCents: 1_000)
        c.setFees(cents: 200, label: nil)
        XCTAssertNil(c.feesLabel)
        XCTAssertEqual(c.feesCents, 200)
    }

    func test_setFees_negativeInput_clampsToZero() {
        let c = cart(subtotalCents: 5_000)
        c.setFees(cents: -99)
        XCTAssertEqual(c.feesCents, 0)
    }

    func test_setFees_zero_removesFee() {
        let c = cart(subtotalCents: 5_000)
        c.setFees(cents: 400, label: "Restocking")
        c.setFees(cents: 0)
        XCTAssertEqual(c.feesCents, 0)
    }

    // MARK: - Combined total

    func test_totalCents_discount_tip_fees_combined() {
        let c = cart(subtotalCents: 10_000)  // $100
        c.setCartDiscountPercent(0.10)        // -$10 → effective subtotal 9000
        c.setTip(cents: 1_350)               // +$13.50 tip
        c.setFees(cents: 500)                // +$5.00 fee
        // total = (10000 - 1000) + 0 tax + 1350 tip + 500 fees
        //       = 9000 + 1350 + 500 = 10850
        XCTAssertEqual(c.totalCents, 10_850)
    }

    func test_totalCents_neverNegative() {
        let c = cart(subtotalCents: 1_000)
        c.setCartDiscount(cents: 999_999)   // wildly over subtotal
        XCTAssertGreaterThanOrEqual(c.totalCents, 0)
    }

    // MARK: - clear() resets all §16.3 fields

    func test_clear_resetsDiscountTipFees() {
        let c = cart(subtotalCents: 5_000)
        c.setCartDiscountPercent(0.10)
        c.setTip(cents: 500)
        c.setFees(cents: 300, label: "Handling")
        c.markHeld(id: 42, note: "Table 3")
        c.clear()

        XCTAssertEqual(c.cartDiscountCents, 0)
        XCTAssertNil(c.cartDiscountPercent)
        XCTAssertEqual(c.tipCents, 0)
        XCTAssertEqual(c.feesCents, 0)
        XCTAssertNil(c.feesLabel)
        XCTAssertNil(c.holdId)
        XCTAssertNil(c.holdNote)
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.totalCents, 0)
    }

    // MARK: - markHeld

    func test_markHeld_persistsIdAndNote() {
        let c = cart(subtotalCents: 2_000)
        c.markHeld(id: 99, note: "VIP table")
        XCTAssertEqual(c.holdId, 99)
        XCTAssertEqual(c.holdNote, "VIP table")
    }

    // MARK: - PosHold JSON snake_case decoding

    func test_posHold_decodesSnakeCase() throws {
        let json = """
        {
            "id": 7,
            "note": "Big spender",
            "items_count": 3,
            "total_cents": 4200,
            "created_at": "2026-04-20T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let hold = try decoder.decode(PosHold.self, from: json)

        XCTAssertEqual(hold.id, 7)
        XCTAssertEqual(hold.note, "Big spender")
        XCTAssertEqual(hold.itemsCount, 3)
        XCTAssertEqual(hold.totalCents, 4_200)
        XCTAssertEqual(hold.createdAt, "2026-04-20T10:00:00Z")
    }

    func test_posHold_decodesNilNote() throws {
        let json = """
        {
            "id": 1,
            "note": null,
            "items_count": 1,
            "total_cents": 100,
            "created_at": "2026-04-20T10:00:00Z"
        }
        """.data(using: .utf8)!

        let hold = try JSONDecoder().decode(PosHold.self, from: json)
        XCTAssertNil(hold.note)
    }

    // MARK: - PosHoldItem snake_case encoding

    func test_posHoldItem_encodesSnakeCase() throws {
        let item = PosHoldItem(
            sku: "SKU-001",
            name: "Widget",
            quantity: 2,
            unitPriceCents: 1000,
            lineTotalCents: 2000
        )
        let data = try JSONEncoder().encode(item)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(dict?["unit_price_cents"], "unit_price_cents must be snake_case")
        XCTAssertNotNil(dict?["line_total_cents"], "line_total_cents must be snake_case")
        XCTAssertEqual(dict?["unit_price_cents"] as? Int, 1000)
        XCTAssertEqual(dict?["line_total_cents"] as? Int, 2000)
        XCTAssertEqual(dict?["quantity"] as? Int, 2)
        XCTAssertEqual(dict?["sku"] as? String, "SKU-001")
        // camelCase keys must NOT appear
        XCTAssertNil(dict?["unitPriceCents"], "camelCase key must not appear in JSON")
        XCTAssertNil(dict?["lineTotalCents"], "camelCase key must not appear in JSON")
    }

    // MARK: - CreatePosHoldRequest snake_case encoding

    func test_createPosHoldRequest_encodesSnakeCase() throws {
        let request = CreatePosHoldRequest(
            items: [],
            tenderNotes: "Cash",
            customerId: 5,
            note: "Hold for pickup"
        )
        let data = try JSONEncoder().encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(dict?["tender_notes"], "tender_notes must be snake_case")
        XCTAssertNotNil(dict?["customer_id"], "customer_id must be snake_case")
        XCTAssertEqual(dict?["note"] as? String, "Hold for pickup")
        XCTAssertNil(dict?["tenderNotes"])
        XCTAssertNil(dict?["customerId"])
    }
}
