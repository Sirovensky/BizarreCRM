import XCTest
@testable import Hardware

final class WeightUnitTests: XCTestCase {

    // MARK: - value(from:)

    func test_grams_identity() {
        XCTAssertEqual(WeightUnit.grams.value(from: 500), 500.0, accuracy: 0.001)
    }

    func test_kilograms_1000g() {
        XCTAssertEqual(WeightUnit.kilograms.value(from: 1000), 1.0, accuracy: 0.001)
    }

    func test_kilograms_500g() {
        XCTAssertEqual(WeightUnit.kilograms.value(from: 500), 0.5, accuracy: 0.001)
    }

    func test_ounces_1000g() {
        XCTAssertEqual(WeightUnit.ounces.value(from: 1000), 35.274, accuracy: 0.01)
    }

    func test_pounds_453g_approx1lb() {
        XCTAssertEqual(WeightUnit.pounds.value(from: 453), 1.0, accuracy: 0.01)
    }

    func test_pounds_0g_is_0() {
        XCTAssertEqual(WeightUnit.pounds.value(from: 0), 0.0, accuracy: 0.001)
    }

    // MARK: - formatted(_:)

    func test_grams_formatted() {
        let w = Weight(grams: 750)
        XCTAssertEqual(WeightUnit.grams.formatted(w), "750 g")
    }

    func test_kg_formatted_1000g() {
        let w = Weight(grams: 1000)
        let str = WeightUnit.kilograms.formatted(w)
        XCTAssertTrue(str.contains("1.000") && str.contains("kg"), "Got: \(str)")
    }

    func test_oz_formatted_contains_oz() {
        let w = Weight(grams: 100)
        let str = WeightUnit.ounces.formatted(w)
        XCTAssertTrue(str.hasSuffix("oz"), "Got: \(str)")
    }

    func test_lb_formatted_contains_lb() {
        let w = Weight(grams: 454)
        let str = WeightUnit.pounds.formatted(w)
        XCTAssertTrue(str.hasSuffix("lb"), "Got: \(str)")
    }

    // MARK: - unitValue convenience

    func test_unitValue_kg_500g() {
        XCTAssertEqual(WeightUnit.kilograms.unitValue(forGrams: 500), 0.5, accuracy: 0.001)
    }

    // MARK: - CaseIterable (all 4 units present)

    func test_allCases_count() {
        XCTAssertEqual(WeightUnit.allCases.count, 4)
    }
}

// MARK: - WeightPriceCalculatorTests

final class WeightPriceCalculatorTests: XCTestCase {

    // MARK: - total(for:)

    func test_poundRate_half_pound() {
        let calc = WeightPriceCalculator(ratePerUnit: Decimal(2.00), unit: .pounds)
        // 227g ≈ 0.5 lb → $1.00
        let total = calc.total(for: Weight(grams: 227))
        // Accept within $0.02 tolerance from gram rounding
        let dbl = (total as NSDecimalNumber).doubleValue
        XCTAssertEqual(dbl, 1.00, accuracy: 0.05)
    }

    func test_gramRate_100g() {
        let calc = WeightPriceCalculator(ratePerUnit: Decimal(0.05), unit: .grams)
        // 100g × $0.05 = $5.00
        let total = calc.total(for: Weight(grams: 100))
        XCTAssertEqual((total as NSDecimalNumber).doubleValue, 5.00, accuracy: 0.001)
    }

    // MARK: - totalCents(for:)

    func test_totalCents_kgRate() {
        let calc = WeightPriceCalculator(ratePerUnit: Decimal(3.99), unit: .kilograms)
        // 500g = 0.5 kg → $1.995 → 200 cents
        let cents = calc.totalCents(for: Weight(grams: 500))
        XCTAssertEqual(cents, 200, "Expected ~200 cents, got \(cents)")
    }

    func test_totalCents_zero_weight() {
        let calc = WeightPriceCalculator(ratePerUnit: Decimal(5.00), unit: .pounds)
        XCTAssertEqual(calc.totalCents(for: Weight(grams: 0)), 0)
    }

    // MARK: - lineItemDescription

    func test_lineItemDescription_notEmpty() {
        let calc = WeightPriceCalculator(ratePerUnit: Decimal(1.50), unit: .pounds)
        let desc = calc.lineItemDescription(for: Weight(grams: 454))
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(desc.contains("lb"), "Description should mention unit: \(desc)")
        XCTAssertTrue(desc.contains("$"), "Description should mention price: \(desc)")
    }

    // MARK: - WeightPricingRule roundtrip

    func test_pricingRule_roundtrip() {
        let rule = WeightPricingRule(ratePerUnit: Decimal(2.99), unit: .kilograms)
        XCTAssertEqual(rule.unit, .kilograms)
        let calc = rule.calculator()
        let cents = calc.totalCents(for: Weight(grams: 1000))
        // 1 kg × $2.99 = $2.99 = 299 cents
        XCTAssertEqual(cents, 299)
    }

    func test_pricingRule_codable() throws {
        let rule = WeightPricingRule(ratePerUnit: Decimal(1.25), unit: .ounces)
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(WeightPricingRule.self, from: data)
        XCTAssertEqual(decoded.unit, .ounces)
        XCTAssertEqual(decoded.rateString, rule.rateString)
    }
}
