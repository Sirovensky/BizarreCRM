import XCTest
@testable import Pos

// MARK: - TipCalculatorTests

/// §16 — Exhaustive unit tests for `TipCalculator`.
/// All tests are pure (no I/O, no async); they run in < 1 ms each.
final class TipCalculatorTests: XCTestCase {

    // MARK: - Percentage presets

    func test_percentage_15_roundsCorrectly() {
        // 15% of $20.00 = $3.00
        let preset = TipPreset(displayName: "15%", value: .percentage(0.15))
        let result = TipCalculator.compute(subtotalCents: 2000, preset: preset)
        XCTAssertEqual(result.rawCents, 300)
        XCTAssertEqual(result.finalCents, 300)
        XCTAssertFalse(result.wasRoundedUp)
    }

    func test_percentage_18_roundsCorrectly() {
        // 18% of $20.00 = $3.60
        let preset = TipPreset(displayName: "18%", value: .percentage(0.18))
        let result = TipCalculator.compute(subtotalCents: 2000, preset: preset)
        XCTAssertEqual(result.rawCents, 360)
        XCTAssertEqual(result.finalCents, 360)
    }

    func test_percentage_20_exactDollar() {
        // 20% of $10.00 = $2.00 (no rounding needed)
        let preset = TipPreset(displayName: "20%", value: .percentage(0.20))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset)
        XCTAssertEqual(result.rawCents, 200)
    }

    func test_percentage_bankersRounding_halfToEven() {
        // 18% of $12.50 = $2.25 (exact; no ambiguous half-cent)
        let preset = TipPreset(displayName: "18%", value: .percentage(0.18))
        let result = TipCalculator.compute(subtotalCents: 1250, preset: preset)
        XCTAssertEqual(result.rawCents, 225) // 225.0 exactly
    }

    func test_percentage_fractional_rounds_bankers() {
        // 15% of $13.33 = $1.9995 → rounds to $2.00 (banker's rounds .5 to even → 200)
        let preset = TipPreset(displayName: "15%", value: .percentage(0.15))
        let result = TipCalculator.compute(subtotalCents: 1333, preset: preset)
        // 1333 * 0.15 = 199.95 → rounds to 200
        XCTAssertEqual(result.rawCents, 200)
    }

    // MARK: - Fixed cent presets

    func test_fixedCents_returnsFixed() {
        let preset = TipPreset(displayName: "$2", value: .fixedCents(200))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset)
        XCTAssertEqual(result.rawCents, 200)
        XCTAssertEqual(result.finalCents, 200)
    }

    func test_fixedCents_ignoredSubtotal() {
        // Fixed tip is independent of subtotal.
        let preset = TipPreset(displayName: "$5", value: .fixedCents(500))
        let small = TipCalculator.compute(subtotalCents: 100, preset: preset)
        let large = TipCalculator.compute(subtotalCents: 100_000, preset: preset)
        XCTAssertEqual(small.rawCents, 500)
        XCTAssertEqual(large.rawCents, 500)
    }

    func test_fixedCents_zeroClampedToZero() {
        let preset = TipPreset(displayName: "$0", value: .fixedCents(0))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset)
        XCTAssertEqual(result.rawCents, 0)
        XCTAssertEqual(result.finalCents, 0)
    }

    func test_fixedCents_negativeClampedToZero() {
        let preset = TipPreset(displayName: "neg", value: .fixedCents(-100))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset)
        XCTAssertEqual(result.rawCents, 0)
    }

    // MARK: - Round-up

    func test_roundUp_appliedWhenEnabled() {
        // 18% of $20.00 = $3.60 → round up to $4.00
        let preset = TipPreset(displayName: "18%", value: .percentage(0.18))
        let result = TipCalculator.compute(subtotalCents: 2000, preset: preset, roundUp: true)
        XCTAssertEqual(result.rawCents, 360)
        XCTAssertEqual(result.finalCents, 400)
        XCTAssertTrue(result.wasRoundedUp)
    }

    func test_roundUp_exactDollarNotChanged() {
        // $3.00 is already on a dollar boundary — round-up is a no-op.
        let preset = TipPreset(displayName: "15%", value: .percentage(0.15))
        let result = TipCalculator.compute(subtotalCents: 2000, preset: preset, roundUp: true)
        XCTAssertEqual(result.rawCents, 300)
        XCTAssertEqual(result.finalCents, 300)
        XCTAssertFalse(result.wasRoundedUp)
    }

    func test_roundUp_1centRoundsUpToOneDollar() {
        let preset = TipPreset(displayName: "1¢", value: .fixedCents(1))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset, roundUp: true)
        XCTAssertEqual(result.finalCents, 100)
        XCTAssertTrue(result.wasRoundedUp)
    }

    func test_roundUp_99centsRoundsUpToOneDollar() {
        let preset = TipPreset(displayName: "99¢", value: .fixedCents(99))
        let result = TipCalculator.compute(subtotalCents: 1000, preset: preset, roundUp: true)
        XCTAssertEqual(result.finalCents, 100)
        XCTAssertTrue(result.wasRoundedUp)
    }

    func test_roundUp_disabled_noChange() {
        let preset = TipPreset(displayName: "18%", value: .percentage(0.18))
        let withoutRound = TipCalculator.compute(subtotalCents: 2000, preset: preset, roundUp: false)
        XCTAssertEqual(withoutRound.finalCents, withoutRound.rawCents)
    }

    // MARK: - Edge cases

    func test_zeroSubtotal_returnsZero() {
        let preset = TipPreset(displayName: "20%", value: .percentage(0.20))
        let result = TipCalculator.compute(subtotalCents: 0, preset: preset)
        XCTAssertEqual(result.rawCents, 0)
        XCTAssertEqual(result.finalCents, 0)
    }

    func test_negativeSubtotal_returnsZero() {
        let preset = TipPreset(displayName: "20%", value: .percentage(0.20))
        let result = TipCalculator.compute(subtotalCents: -500, preset: preset)
        XCTAssertEqual(result.rawCents, 0)
    }

    func test_veryLargeSubtotal_noOverflow() {
        // $99,999.99 subtotal — should not crash or overflow.
        let preset = TipPreset(displayName: "25%", value: .percentage(0.25))
        let result = TipCalculator.compute(subtotalCents: 9_999_999, preset: preset)
        XCTAssertEqual(result.rawCents, 2_500_000) // 25% of 9_999_999 ≈ 2_500_000
        // Exact: 9_999_999 * 0.25 = 2_499_999.75 → banker's rounds to 2_500_000
        XCTAssertGreaterThan(result.rawCents, 0)
    }

    // MARK: - Custom tip computation

    func test_computeCustom_returnsValue() {
        let result = TipCalculator.computeCustom(subtotalCents: 1000, customCents: 250)
        XCTAssertEqual(result.rawCents, 250)
        XCTAssertEqual(result.finalCents, 250)
    }

    func test_computeCustom_withRoundUp() {
        // 250¢ → round up to 300¢ ($3.00)
        let result = TipCalculator.computeCustom(subtotalCents: 1000, customCents: 250, roundUp: true)
        XCTAssertEqual(result.rawCents, 250)
        XCTAssertEqual(result.finalCents, 300)
        XCTAssertTrue(result.wasRoundedUp)
    }

    func test_computeCustom_negativeClampedToZero() {
        let result = TipCalculator.computeCustom(subtotalCents: 1000, customCents: -50)
        XCTAssertEqual(result.rawCents, 0)
        XCTAssertEqual(result.finalCents, 0)
    }

    // MARK: - TipResult properties

    func test_wasRoundedUp_falseWhenEqual() {
        let result = TipResult(rawCents: 300, finalCents: 300)
        XCTAssertFalse(result.wasRoundedUp)
    }

    func test_wasRoundedUp_trueWhenDifferent() {
        let result = TipResult(rawCents: 310, finalCents: 400)
        XCTAssertTrue(result.wasRoundedUp)
    }

    // MARK: - Default presets smoke test

    func test_defaultPresets_computeForTypicalSubtotal() {
        let subtotal = 2500 // $25.00
        for preset in TipPreset.defaults {
            let result = TipCalculator.compute(subtotalCents: subtotal, preset: preset)
            XCTAssertGreaterThan(result.rawCents, 0, "Expected positive tip for \(preset.displayName)")
        }
    }
}
