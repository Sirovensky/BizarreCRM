import XCTest
@testable import Pos

/// Focused tests for the `DiscountEngine` scenarios called out in §16 spec:
/// mixed rules, stacking order (percent-then-fixed), minimum threshold gate,
/// and coupon code format validation integration.
///
/// These complement the exhaustive `DiscountEngineTests.swift` at the root
/// of `PosTests/` which was shipped with the initial engine implementation.
final class DiscountEngineMixedTests: XCTestCase {

    private let engine = DiscountEngine()

    // MARK: - Helpers

    private func item(
        id: UUID = UUID(),
        sku: String? = nil,
        category: String? = nil,
        quantity: Int = 1,
        subtotalCents: Int
    ) -> CartItemSnapshot {
        CartItemSnapshot(id: id, sku: sku, category: category,
                         quantity: quantity, lineSubtotalCents: subtotalCents)
    }

    private func cart(items: [CartItemSnapshot], subtotalCents: Int? = nil) -> DiscountCartSnapshot {
        let total = subtotalCents ?? items.reduce(0) { $0 + $1.lineSubtotalCents }
        return DiscountCartSnapshot(items: items, subtotalCents: total)
    }

    private func rule(
        id: String = UUID().uuidString,
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
        managerApproval: Bool = false
    ) -> DiscountRule {
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

    // MARK: - Mixed percent + flat rules (stackable)

    /// Percent discount is applied first (to the gross basis), then the flat
    /// discount is also applied to the *same* basis — both are summed.
    /// The spec says "percent-then-fixed" refers to application order when
    /// stacking; since both use the same original basis the total is just their sum.
    func test_mixed_percentAndFlat_stackable_bothApplied() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "pct", percent: 0.10, stackable: true),   // 1 000
            rule(id: "flt", flat: 500, stackable: true)         //   500
        ])
        XCTAssertEqual(result.cartApplications.count, 2)
        XCTAssertEqual(result.totalDiscountCents, 1_500)
    }

    func test_mixed_percentAndFlat_stackable_orderIndependent() async {
        // Swapping order of rules should not change total
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)

        let resultA = await engine.apply(cart: c, rules: [
            rule(id: "pct", percent: 0.10, stackable: true),
            rule(id: "flt", flat: 300,     stackable: true)
        ])
        let resultB = await engine.apply(cart: c, rules: [
            rule(id: "flt", flat: 300,     stackable: true),
            rule(id: "pct", percent: 0.10, stackable: true)
        ])
        XCTAssertEqual(resultA.totalDiscountCents, resultB.totalDiscountCents)
    }

    // MARK: - Non-stackable: best-for-customer wins

    func test_nonStackable_percentVsFlat_largerWins_isPercent() async {
        let c = cart(items: [item(subtotalCents: 10_000)], subtotalCents: 10_000)
        // 20% = 2000 > flat 500 → percent wins
        let result = await engine.apply(cart: c, rules: [
            rule(id: "p", percent: 0.20, stackable: false),
            rule(id: "f", flat:    500,  stackable: false)
        ])
        XCTAssertEqual(result.cartApplications.count, 1)
        XCTAssertEqual(result.cartApplications.first?.discountCents, 2_000)
    }

    func test_nonStackable_percentVsFlat_largerWins_isFlat() async {
        let c = cart(items: [item(subtotalCents: 1_000)], subtotalCents: 1_000)
        // 5% = 50 < flat 200 → flat wins
        let result = await engine.apply(cart: c, rules: [
            rule(id: "p", percent: 0.05, stackable: false),
            rule(id: "f", flat:    200,  stackable: false)
        ])
        XCTAssertEqual(result.cartApplications.count, 1)
        XCTAssertEqual(result.cartApplications.first?.discountCents, 200)
    }

    // MARK: - Mixed stackable + non-stackable (spec: §16 stacking order)

    func test_mixedStackable_nonStackable_combined_percentThenFixed() async {
        let c = cart(items: [item(subtotalCents: 20_000)], subtotalCents: 20_000)
        // stackable percent 10% = 2000
        // stackable flat $5 = 500
        // non-stackable flat $8 = 800  (wins over non-stackable flat $3 = 300)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "sp",  percent: 0.10, stackable: true),
            rule(id: "sf",  flat:    500,  stackable: true),
            rule(id: "ns1", flat:    800,  stackable: false),
            rule(id: "ns2", flat:    300,  stackable: false)
        ])
        // 2000 + 500 + 800 = 3300
        XCTAssertEqual(result.totalDiscountCents, 3_300)
    }

    // MARK: - Minimum cart threshold gate

    func test_minCartTotal_strictlyBelow_ruleSkipped() async {
        let c = cart(items: [item(subtotalCents: 4_999)], subtotalCents: 4_999)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, minCartTotal: 5_000)
        ])
        XCTAssertEqual(result.totalDiscountCents, 0)
    }

    func test_minCartTotal_exactlyMet_ruleApplied() async {
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, minCartTotal: 5_000)
        ])
        XCTAssertEqual(result.totalDiscountCents, 500)
    }

    func test_minCartTotal_above_ruleApplied() async {
        let c = cart(items: [item(subtotalCents: 7_500)], subtotalCents: 7_500)
        let result = await engine.apply(cart: c, rules: [
            rule(flat: 300, minCartTotal: 5_000)
        ])
        XCTAssertEqual(result.totalDiscountCents, 300)
    }

    func test_minCartTotal_multipleRules_onlyEligibleApplied() async {
        let c = cart(items: [item(subtotalCents: 6_000)], subtotalCents: 6_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "low",  flat: 200, minCartTotal: 5_000),  // eligible (6000 >= 5000)
            rule(id: "high", flat: 500, minCartTotal: 10_000)  // ineligible
        ])
        XCTAssertEqual(result.totalDiscountCents, 200)
    }

    // MARK: - Coupon format integration via CouponValidator

    func test_couponFormat_validCode_passesValidator() {
        let validator = CouponValidator()
        let result = validator.validateFormat("SUMMER25")
        XCTAssertTrue(result.isValid, "Expected SUMMER25 to pass format check")
    }

    func test_couponFormat_emptyCode_failsValidator() {
        let validator = CouponValidator()
        let result = validator.validateFormat("")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for empty string") }
    }

    func test_couponFormat_tooShort_failsValidator() {
        let validator = CouponValidator()
        let result = validator.validateFormat("AB")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for 2-char code") }
    }

    func test_couponFormat_tooLong_failsValidator() {
        let validator = CouponValidator()
        let code = String(repeating: "X", count: CouponValidator.maxCodeLength + 1)
        let result = validator.validateFormat(code)
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for oversized code") }
    }

    func test_couponExpiry_validatedBeforeNetworkCall() {
        let validator = CouponValidator()
        let past = Date(timeIntervalSinceNow: -1)
        let coupon = CouponCode(id: "c1", code: "EXPIRED", ruleId: "r1", ruleName: "10%", expiresAt: past)
        let result = validator.validate(rawCode: "EXPIRED", knownCoupon: coupon)
        if case .expired = result { XCTAssert(true) }
        else { XCTFail("Expected .expired to block network call, got \(result)") }
    }

    // MARK: - Combined: threshold gate + stacking

    func test_threshold_and_stacking_onlyEligibleRulesStack() async {
        // Cart is $80 — one rule requires $100 minimum (blocked), two don't (both apply + stack)
        let subtotal = 8_000
        let c = cart(items: [item(subtotalCents: subtotal)], subtotalCents: subtotal)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "a", flat: 200, stackable: true, minCartTotal: nil),
            rule(id: "b", flat: 300, stackable: true, minCartTotal: nil),
            rule(id: "c", flat: 500, stackable: true, minCartTotal: 10_000)  // blocked
        ])
        XCTAssertEqual(result.totalDiscountCents, 500)  // 200 + 300 only
    }

    // MARK: - Total clamped to subtotal

    func test_stackingDoesNotExceedSubtotal() async {
        let c = cart(items: [item(subtotalCents: 1_000)], subtotalCents: 1_000)
        let result = await engine.apply(cart: c, rules: [
            rule(id: "a", flat: 700, stackable: true),
            rule(id: "b", flat: 700, stackable: true)
        ])
        XCTAssertLessThanOrEqual(result.totalDiscountCents, 1_000)
    }

    // MARK: - Manager approval flag propagation

    func test_managerApprovalRule_flagsResult() async {
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.50, managerApproval: true)
        ])
        XCTAssertTrue(result.requiresManagerApproval)
    }

    func test_onlyNonApprovalRules_doesNotFlagResult() async {
        let c = cart(items: [item(subtotalCents: 5_000)], subtotalCents: 5_000)
        let result = await engine.apply(cart: c, rules: [
            rule(percent: 0.10, managerApproval: false)
        ])
        XCTAssertFalse(result.requiresManagerApproval)
    }
}
