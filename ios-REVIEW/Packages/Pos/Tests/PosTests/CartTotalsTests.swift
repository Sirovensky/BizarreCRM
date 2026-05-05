import XCTest
@testable import Pos

@MainActor
final class CartTotalsTests: XCTestCase {

    // Mixed per-line tax: $10 @ 7% + $5 untaxed → tax 70¢, total $15.70.
    func test_subtotal_tax_total_withMixedRates() {
        let cart = Cart()
        cart.add(CartItem(
            name: "Taxed",
            quantity: 1,
            unitPrice: Decimal(string: "10.00")!,
            taxRate: Decimal(string: "0.07")
        ))
        cart.add(CartItem(
            name: "Exempt",
            quantity: 1,
            unitPrice: Decimal(string: "5.00")!,
            taxRate: nil
        ))

        XCTAssertEqual(cart.subtotalCents, 1500)
        XCTAssertEqual(cart.taxCents, 70)
        XCTAssertEqual(cart.totalCents, 1570)
    }

    // Two taxed lines with different rates sum independently.
    func test_tax_sumsPerLineNotGlobally() {
        let cart = Cart()
        cart.add(CartItem(
            name: "A",
            quantity: 1,
            unitPrice: Decimal(string: "100.00")!,
            taxRate: Decimal(string: "0.05")
        ))
        cart.add(CartItem(
            name: "B",
            quantity: 1,
            unitPrice: Decimal(string: "100.00")!,
            taxRate: Decimal(string: "0.10")
        ))
        // Line 1 tax: $5.00 (500). Line 2 tax: $10.00 (1000). Subtotal 200
        // × 1 = $200 = 20000.
        XCTAssertEqual(cart.subtotalCents, 20000)
        XCTAssertEqual(cart.taxCents, 1500)
        XCTAssertEqual(cart.totalCents, 21500)
    }

    // Tax applies on the discounted subtotal — not the gross.
    func test_tax_appliesAfterDiscount() {
        let cart = Cart()
        cart.add(CartItem(
            name: "A",
            quantity: 1,
            unitPrice: Decimal(string: "100.00")!,
            taxRate: Decimal(string: "0.10"),
            discountCents: 2000
        ))
        // Net $80 × 10% = $8.00 tax → total $88.00.
        XCTAssertEqual(cart.subtotalCents, 8000)
        XCTAssertEqual(cart.taxCents, 800)
        XCTAssertEqual(cart.totalCents, 8800)
    }

    // Bankers rounding keeps the "1.99 × 3 × 7%" calc from drifting.
    func test_tax_bankersRounding_onDecimalLine() {
        let cart = Cart()
        cart.add(CartItem(
            name: "A",
            quantity: 3,
            unitPrice: Decimal(string: "1.99")!,
            taxRate: Decimal(string: "0.07")
        ))
        // Line subtotal $5.97 → tax $0.4179 → banker-rounds to $0.42 (42¢).
        XCTAssertEqual(cart.subtotalCents, 597)
        XCTAssertEqual(cart.taxCents, 42)
        XCTAssertEqual(cart.totalCents, 639)
    }

    func test_itemQuantity_sumsQuantitiesAcrossLines() {
        let cart = Cart()
        cart.add(CartItem(name: "A", quantity: 2, unitPrice: 1))
        cart.add(CartItem(name: "B", quantity: 3, unitPrice: 1))
        XCTAssertEqual(cart.itemQuantity, 5)
        XCTAssertEqual(cart.lineCount, 2)
    }

    // CartMath.toCents is load-bearing — keep it correct.
    func test_cartMath_toCents_banker() {
        // 2.125 → 2.12 (banker rounds half-to-even). 2.135 → 2.14.
        XCTAssertEqual(CartMath.toCents(Decimal(string: "2.125")!), 212)
        XCTAssertEqual(CartMath.toCents(Decimal(string: "2.135")!), 214)
    }

    func test_cartMath_formatCents_roundTripsToUsdString() {
        let formatted = CartMath.formatCents(12345)
        // Locale-dependent, but must at least include the digits.
        XCTAssertTrue(formatted.contains("123"), "\(formatted) missing dollars")
        XCTAssertTrue(formatted.contains("45"), "\(formatted) missing cents")
    }
}
