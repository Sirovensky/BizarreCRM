import XCTest
@testable import Inventory

// MARK: - §6.8 Asset Depreciation Tests
//
// Pure-Swift coverage for AssetDepreciationCalculator + AssetBookValueSummary.

final class AssetDepreciationTests: XCTestCase {

    // MARK: - Linear

    func test_linear_atStart_bookValueEqualsCost() {
        let input = AssetDepreciationInput(
            costCents: 120_000,
            salvageValueCents: 20_000,
            usefulLifeMonths: 36,
            monthsInService: 0,
            method: .linear
        )
        XCTAssertEqual(AssetDepreciationCalculator.bookValueCents(input), 120_000)
        XCTAssertEqual(AssetDepreciationCalculator.accumulatedDepreciationCents(input), 0)
    }

    func test_linear_midLife_isHalfDepreciated() {
        // Cost 1200, salvage 200 → depreciable 1000.
        // Halfway through 24 months → expect ~700 book value.
        let input = AssetDepreciationInput(
            costCents: 120_000,
            salvageValueCents: 20_000,
            usefulLifeMonths: 24,
            monthsInService: 12,
            method: .linear
        )
        let bv = AssetDepreciationCalculator.bookValueCents(input)
        XCTAssertEqual(bv, 70_000)
        XCTAssertEqual(AssetDepreciationCalculator.accumulatedDepreciationCents(input), 50_000)
    }

    func test_linear_endOfLife_clampsAtSalvage() {
        let input = AssetDepreciationInput(
            costCents: 100_000,
            salvageValueCents: 10_000,
            usefulLifeMonths: 12,
            monthsInService: 24,   // overshoot
            method: .linear
        )
        XCTAssertEqual(AssetDepreciationCalculator.bookValueCents(input), 10_000)
    }

    // MARK: - Declining balance

    func test_decliningBalance_firstMonth_appliesRate() {
        // rate = 2/24 ≈ 0.0833 → after 1 month BV ≈ 100k * (1 - 0.0833) ≈ 91666
        let input = AssetDepreciationInput(
            costCents: 100_000,
            salvageValueCents: 0,
            usefulLifeMonths: 24,
            monthsInService: 1,
            method: .decliningBalance
        )
        let bv = AssetDepreciationCalculator.bookValueCents(input)
        XCTAssertEqual(bv, 91_667, accuracy: 1)
    }

    func test_decliningBalance_clampsAtSalvage() {
        // After enough months, declining-balance must not drop below salvage.
        let input = AssetDepreciationInput(
            costCents: 100_000,
            salvageValueCents: 10_000,
            usefulLifeMonths: 12,
            monthsInService: 200,
            method: .decliningBalance
        )
        XCTAssertEqual(AssetDepreciationCalculator.bookValueCents(input), 10_000)
    }

    // MARK: - Defensive

    func test_zeroLife_returnsCost() {
        let input = AssetDepreciationInput(
            costCents: 50_000,
            salvageValueCents: 0,
            usefulLifeMonths: 0,
            monthsInService: 12,
            method: .linear
        )
        XCTAssertEqual(AssetDepreciationCalculator.bookValueCents(input), 50_000)
    }

    func test_negativeMonths_treatedAsZero() {
        let input = AssetDepreciationInput(
            costCents: 100_000,
            salvageValueCents: 0,
            usefulLifeMonths: 24,
            monthsInService: -5,
            method: .linear
        )
        XCTAssertEqual(AssetDepreciationCalculator.bookValueCents(input), 100_000)
    }

    func test_monthlyRate_zeroWhenNoMonthsInService() {
        let input = AssetDepreciationInput(
            costCents: 100_000,
            salvageValueCents: 0,
            usefulLifeMonths: 24,
            monthsInService: 0,
            method: .linear
        )
        XCTAssertEqual(AssetDepreciationCalculator.monthlyDepreciationCents(input), 0)
    }

    // MARK: - Dashboard data

    func test_summary_accumulatedDepreciation() {
        let summary = AssetBookValueSummary(
            totalCostCents: 100_000,
            totalBookValueCents: 60_000,
            activeAssetCount: 5,
            fullyDepreciatedCount: 1,
            snapshotAt: Date()
        )
        XCTAssertEqual(summary.accumulatedDepreciationCents, 40_000)
        XCTAssertEqual(summary.depreciationFraction, 0.4, accuracy: 0.001)
    }

    func test_summary_zeroCost_safeFraction() {
        let summary = AssetBookValueSummary(
            totalCostCents: 0,
            totalBookValueCents: 0,
            activeAssetCount: 0,
            fullyDepreciatedCount: 0,
            snapshotAt: Date()
        )
        XCTAssertEqual(summary.depreciationFraction, 0)
        XCTAssertEqual(summary.accumulatedDepreciationCents, 0)
    }

    func test_method_displayNames_nonEmpty() {
        for m in DepreciationMethod.allCases {
            XCTAssertFalse(m.displayName.isEmpty)
        }
    }
}
