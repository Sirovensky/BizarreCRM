import XCTest
@testable import Hardware

final class WeightTests: XCTestCase {

    // MARK: - Basic construction

    func test_grams_roundtrip() {
        let w = Weight(grams: 500, isStable: true)
        XCTAssertEqual(w.grams, 500)
    }

    func test_isStable_default_true() {
        let w = Weight(grams: 100)
        XCTAssertTrue(w.isStable)
    }

    func test_isStable_false_preserved() {
        let w = Weight(grams: 100, isStable: false)
        XCTAssertFalse(w.isStable)
    }

    // MARK: - Ounce conversion

    func test_ounces_oneGram() {
        let w = Weight(grams: 1)
        XCTAssertEqual(w.ounces, 0.035274, accuracy: 0.000001)
    }

    func test_ounces_zero() {
        XCTAssertEqual(Weight.zero.ounces, 0.0, accuracy: 0.000001)
    }

    func test_ounces_1000g() {
        let w = Weight(grams: 1000)
        XCTAssertEqual(w.ounces, 35.274, accuracy: 0.001)
    }

    // MARK: - Pound conversion

    func test_pounds_oneGram() {
        let w = Weight(grams: 1)
        XCTAssertEqual(w.pounds, 0.0022046, accuracy: 0.000001)
    }

    func test_pounds_453g_isApprox1lb() {
        let w = Weight(grams: 453)
        XCTAssertEqual(w.pounds, 1.0, accuracy: 0.01)
    }

    func test_pounds_1000g() {
        let w = Weight(grams: 1000)
        XCTAssertEqual(w.pounds, 2.2046, accuracy: 0.001)
    }

    // MARK: - Factory from ounces

    func test_fromOunces_roundtrip() {
        let oz = 16.0
        let w = Weight.fromOunces(oz)
        // 16 oz → ~453 g
        XCTAssertEqual(w.grams, 454, accuracy: 2) // rounding tolerance ±2g
    }

    func test_fromOunces_zero() {
        XCTAssertEqual(Weight.fromOunces(0).grams, 0)
    }

    // MARK: - Factory from pounds

    func test_fromPounds_roundtrip() {
        let lb = 1.0
        let w = Weight.fromPounds(lb)
        XCTAssertEqual(w.grams, 454, accuracy: 2)
    }

    func test_fromPounds_zero() {
        XCTAssertEqual(Weight.fromPounds(0).grams, 0)
    }

    // MARK: - Comparable

    func test_comparison_lessThan() {
        XCTAssertLessThan(Weight(grams: 100), Weight(grams: 200))
    }

    func test_comparison_equal() {
        XCTAssertEqual(Weight(grams: 100), Weight(grams: 100))
    }

    // MARK: - Hashable

    func test_hashable_sameGramsAndStability_equal() {
        let a = Weight(grams: 250, isStable: true)
        let b = Weight(grams: 250, isStable: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_differentGrams_notEqual() {
        XCTAssertNotEqual(Weight(grams: 100), Weight(grams: 200))
    }

    // MARK: - Description

    func test_description_belowKilogram() {
        let w = Weight(grams: 500)
        XCTAssertTrue(w.description.contains("500 g"))
    }

    func test_description_aboveKilogram() {
        let w = Weight(grams: 1500)
        XCTAssertTrue(w.description.contains("kg"))
    }

    func test_description_unstableTag() {
        let w = Weight(grams: 200, isStable: false)
        XCTAssertTrue(w.description.contains("unstable"))
    }

    // MARK: - Zero

    func test_zero_gramsIsZero() {
        XCTAssertEqual(Weight.zero.grams, 0)
    }

    func test_zero_isStable() {
        XCTAssertTrue(Weight.zero.isStable)
    }
}

// MARK: - XCTAssertEqual(Int, Int, accuracy:) helper
// XCTest does not have an Int overload with accuracy; bridge through Double.
private func XCTAssertEqual(_ a: Int, _ b: Int, accuracy: Int, file: StaticString = #file, line: UInt = #line) {
    XCTAssertEqual(Double(a), Double(b), accuracy: Double(accuracy), file: file, line: line)
}
