import XCTest
@testable import Pos

/// Tests for `DiscountEngine.apply(cart:rules:)`.
/// Covers: whole scope, lineItem scope, category scope, SKU scope,
/// stackable vs non-stackable, minCartTotal threshold, expiry, manager approval.
final class DiscountEngineTests: XCTestCase {

    private let engine = DiscountEngine()

    // MARK: - Helpers

    private func item(id: UUID = UUID(), sku: String? = nil, category: String? = nil,
                      quantity: Int = 1, subtotalCents: Int = 1000) -> CartItemSnapshot {
        CartItemSnapshot(id: id, sku: sku, category: category,
                         quantity: quantity, lineSubtotalCents: subtotalCents)
    }

    private func cart(items: [CartItemSnapshot], subtotalCents: Int? = nil) -> DiscountCartSnapshot {
        let total = subtotalCents ?? items.reduce(0) { $0 + $1.lineSubtotalCents }
        return DiscountCartSnapshot(items: items, subtotalCents: total)
    }

    private func rule(id: String = UUID().uuidString,
                      name: String = "Test",
                      scope: DiscountScope = .whole,
                      matcher: String = "",
                      percent: Double? = nil,
                      flat: Int? = nil,
                      minCartTotal: Int? = nil,
                      minQuantity: Int? = nil,
                      validFrom: Date? = nil,
                      validTo: Date? = nil,
                      stackable: Bool = true,
                      managerApproval: Bool = false) -> DiscountRule {
        DiscountRule(
            id: id,
            name: name,
            scope: scope,
            matcher: matcher,
            discountPercent: percent,
            discountFlatCents: flat,
            minQuantity: minQuantity,
            minCartTotalCents: minCartTotal,
            validFrom: validFrom,
            validTo: validTo,
            stackable: stackable,
            managerApprovalRequired: managerApproval
        )
    }

    // MARK: - Empty cart / no rules

    func test_emptyCart_returnsEmpty() async {
        let result = await engine.apply(cart: cart(items: []), rules: [
            rule(percent: 0.10)
        ])
        XCTAssertEqual(result.totalDiscountCents, 0)
        XCTAssertTrue(result.cartApplications.isEmpty)
    }

    func test_noRules_returnsEmpty() async {
        let c = cart(items: [item(subtotalCents: 5000)], subtotalCents: 5000)
        let result = await engine.apply(cart: c, rules: [])
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    // MARK: - Whole scope

    func test_wholeScope_percentRule_appliesCorrectly() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [rule(percent: 0.10)])
        XCTAssertEqual(result.totalDiscountCents, 1_000)
        XCTAssertEqual(result.cartApplications.count, 1)
    }

    func test_wholeScope_flatRule_appliesCorrectly() async {
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [rule(flat: 500)])
        XCTAssertEqual(result.totalDiscountCents, 500)
    }

    func test_wholeScope_discountClampedToSubtotal() async {
        let c = cart(items: [item(subtotalCents: 500)], subtotalCents: 500)
        let result = await engine.apply(cart: c, rules: [rule(flat: 99_999)])
        XCTAssertLessThanOrEqual(result.totalDiscountCents, 500)
    }

    // MARK: - lineItem scope

    func test_lineItem_appliesPerLine() async {
        let id1 = UUID()
        let id2 = UUID()
        let c = cart(items: [
            item(id: id1, subtotalCents: 2_000),
            item(id: id2, subtotalCents: 3_000)
        ], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .lineItem, flat: 200)
        ])
        // 200 off each line → 400 total; but clamped to subtotal 5000
        XCTAssertEqual(result.lineApplications[id1]?.first?.discountCents, 200)
        XCTAssertEqual(result.lineApplications[id2]?.first?.discountCents, 200)
    }

    // MARK: - Category scope

    func test_categoryScope_onlyMatchingLinesDiscount() async {
        let id1 = UUID()
        let id2 = UUID()
        let c = cart(items: [
            item(id: id1, category: "Electronics", subtotalCents: 5_000),
            item(id: id2, category: "Clothing", subtotalCents: 2_000)
        ], subtotalCents: 7_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .category, matcher: "Electronics", percent: 0.20)
        ])
        XCTAssertNotNil(result.lineApplications[id1])
        XCTAssertNil(result.lineApplications[id2])
        XCTAssertEqual(result.lineApplications[id1]?.first?.discountCents, 1_000)
    }

    // MARK: - SKU scope

    func test_skuScope_regexMatch() async {
        let matchId = UUID()
        let noMatchId = UUID()
        let c = cart(items: [
            item(id: matchId, sku: "WIDGET-001", subtotalCents: 3_000),
            item(id: noMatchId, sku: "SERVICE-99", subtotalCents: 2_000)
        ], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .sku, matcher: "^WIDGET-", percent: 0.10)
        ])
        XCTAssertNotNil(result.lineApplications[matchId])
        XCTAssertNil(result.lineApplications[noMatchId])
    }

    func test_skuScope_noSku_doesNotMatch() async {
        let id = UUID()
        let c = cart(items: [item(id: id, sku: nil, subtotalCents: 1_000)], subtotalCents: 1_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .sku, matcher: ".*", percent: 0.10)
        ])
        XCTAssertNil(result.lineApplications[id])
    }

    // MARK: - Stackable vs non-stackable

    func test_stackableRules_summed() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "r1", percent: 0.10, stackable: true),
            rule(id: "r2", percent: 0.05, stackable: true)
        ])
        // 1000 + 500 = 1500, within 10000
        XCTAssertEqual(result.cartApplications.count, 2)
        XCTAssertEqual(result.totalDiscountCents, 1_500)
    }

    func test_nonStackableRules_bestWins() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "r1", percent: 0.10, stackable: false),  // 1000
            rule(id: "r2", percent: 0.20, stackable: false)   // 2000 — wins
        ])
        // Only 1 non-stackable winner
        XCTAssertEqual(result.cartApplications.count, 1)
        XCTAssertEqual(result.cartApplications.first?.discountCents, 2_000)
    }

    func test_mixedStackable_nonStackable_combined() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "s1", flat: 300, stackable: true),    // always applied
            rule(id: "n1", flat: 500, stackable: false),   // 500
            rule(id: "n2", flat: 800, stackable: false)    // 800 — wins
        ])
        // stackable 300 + best non-stackable 800 = 1100
        XCTAssertEqual(result.totalDiscountCents, 1_100)
    }

    // MARK: - Min cart total threshold

    func test_minCartTotal_belowThreshold_ruleSkipped() async {
        let c = cart(items: [item(subtotalCents: 2_000)], subtotalCents: 2_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, minCartTotal: 5_000)
        ])
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_minCartTotal_meetsThreshold_ruleApplied() async {
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, minCartTotal: 5_000)
        ])
        XCTAssertEqual(result.totalDiscountCents, 500)
    }

    // MARK: - Min quantity

    func test_minQuantity_belowThreshold_lineSkipped() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 1, subtotalCents: 1_000)], subtotalCents: 1_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .lineItem, percent: 0.10, minQuantity: 3)
        ])
        XCTAssertNil(result.lineApplications[id])
    }

    func test_minQuantity_meetsThreshold_lineDiscounted() async {
        let id = UUID()
        let c = cart(items: [item(id: id, quantity: 3, subtotalCents: 3_000)], subtotalCents: 3_000)
        let result = await engine.apply(cart: c, rules: [
            rule(scope: .lineItem, percent: 0.10, minQuantity: 3)
        ])
        XCTAssertNotNil(result.lineApplications[id])
    }

    // MARK: - Expiry

    func test_expiredRule_notApplied() async {
        let yesterday = Date(timeIntervalSinceNow: -86_400)
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, validTo: yesterday)
        ])
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_futureRule_notApplied() async {
        let tomorrow = Date(timeIntervalSinceNow: 86_400)
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, validFrom: tomorrow)
        ])
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_activeRule_appliedWithinWindow() async {
        let yesterday = Date(timeIntervalSinceNow: -86_400)
        let tomorrow  = Date(timeIntervalSinceNow:  86_400)
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, validFrom: yesterday, validTo: tomorrow)
        ])
        XCTAssertEqual(result.totalDiscountCents, 500)
    }

    // MARK: - Manager approval

    func test_managerApprovalRequired_flagged() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.50, managerApproval: true)
        ])
        XCTAssertTrue(result.requiresManagerApproval)
    }

    func test_noManagerApproval_notFlagged() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, managerApproval: false)
        ])
        XCTAssertFalse(result.requiresManagerApproval)
    }

    // MARK: - Cart.applyDiscountResult integration

    @MainActor
    func test_cart_applyDiscountResult_updatesFields() async {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 100))
        let result = DiscountResult(
            lineApplications: [:],
            cartApplications: [DiscountApplication(ruleId: "r1", ruleName: "10% off", scope: .whole, discountCents: 1000)],
            totalDiscountCents: 1_000,
            requiresManagerApproval: true
        )
        cart.applyDiscountResult(result)
        XCTAssertEqual(cart.effectiveDiscountCents, 1_000)
        XCTAssertTrue(cart.discountRequiresManagerApproval)
        XCTAssertEqual(cart.cartDiscountApplications.count, 1)
    }

    // MARK: - Coupon integration on Cart

    @MainActor
    func test_cart_applyCoupon_addsAndAccumulates() {
        let cart = Cart()
        let coupon = CouponCode(id: "c1", code: "SAVE10", ruleId: "r1", ruleName: "10% off")
        cart.applyCoupon(coupon, discountCents: 500)
        XCTAssertEqual(cart.appliedCoupons.count, 1)
        XCTAssertEqual(cart.couponDiscountCents, 500)
    }

    @MainActor
    func test_cart_removeCoupon_decrementsCouponDiscount() {
        let cart = Cart()
        let coupon = CouponCode(id: "c1", code: "SAVE10", ruleId: "r1", ruleName: "10% off")
        cart.applyCoupon(coupon, discountCents: 500)
        cart.removeCoupon(id: "c1", discountCents: 500)
        XCTAssertTrue(cart.appliedCoupons.isEmpty)
        XCTAssertEqual(cart.couponDiscountCents, 0)
    }

    @MainActor
    func test_cart_clear_resetsCouponsAndDiscounts() {
        let cart = Cart()
        cart.add(CartItem(name: "Widget", unitPrice: 50))
        let coupon = CouponCode(id: "c1", code: "SAVE10", ruleId: "r1", ruleName: "10% off")
        cart.applyCoupon(coupon, discountCents: 200)
        cart.applyDiscountResult(DiscountResult(
            lineApplications: [:],
            cartApplications: [],
            totalDiscountCents: 500,
            requiresManagerApproval: false
        ))
        cart.clear()

        XCTAssertTrue(cart.appliedCoupons.isEmpty)
        XCTAssertEqual(cart.couponDiscountCents, 0)
        XCTAssertTrue(cart.appliedDiscounts.isEmpty)
        XCTAssertFalse(cart.discountRequiresManagerApproval)
    }
}
