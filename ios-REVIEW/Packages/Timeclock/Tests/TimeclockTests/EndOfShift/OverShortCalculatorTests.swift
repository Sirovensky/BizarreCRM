import XCTest
@testable import Timeclock

/// §14.10 — Tests for `OverShortCalculator` and `EndShiftSummary`.
final class OverShortCalculatorTests: XCTestCase {

    private let calc = OverShortCalculator()

    // MARK: - OverShortCalculator

    func test_balancedDrawerReturnsZeroOverShort() {
        var denoms = CashDenomination.defaultDenominations
        // 1×$20 + 1×$5 = $25.00 = 2500 cents
        denoms[2].count = 1  // $20
        denoms[4].count = 1  // $5
        let (counted, overShort) = calc.compute(denominations: denoms, expectedCents: 2500)
        XCTAssertEqual(counted, 2500)
        XCTAssertEqual(overShort, 0)
    }

    func test_overBy100CentsProducesPositiveResult() {
        var denoms = CashDenomination.defaultDenominations
        denoms[6].count = 1  // $1
        let (_, overShort) = calc.compute(denominations: denoms, expectedCents: 0)
        XCTAssertEqual(overShort, 100)
    }

    func test_shortBy50CentsProducesNegativeResult() {
        let denoms = CashDenomination.defaultDenominations  // all zeros
        let (_, overShort) = calc.compute(denominations: denoms, expectedCents: 50)
        XCTAssertEqual(overShort, -50)
    }

    // MARK: - EndShiftSummary.requiresManagerSignOff

    func test_overBy100CentsDoesNotRequireSignOff() {
        let s = EndShiftSummary(
            salesCount: 5, grossCents: 2000, tipsCents: 0,
            cashExpectedCents: 1000, cashCountedCents: 1100,
            itemsSold: 3, voidCount: 0
        )
        XCTAssertFalse(s.requiresManagerSignOff)
    }

    func test_shortBy300CentsRequiresSignOff() {
        let s = EndShiftSummary(
            salesCount: 5, grossCents: 2000, tipsCents: 0,
            cashExpectedCents: 1000, cashCountedCents: 700,
            itemsSold: 3, voidCount: 0
        )
        XCTAssertTrue(s.requiresManagerSignOff)
    }

    func test_exactly200CentsDeltaDoesNotRequireSignOff() {
        let s = EndShiftSummary(
            salesCount: 0, grossCents: 0, tipsCents: 0,
            cashExpectedCents: 200, cashCountedCents: 0,
            itemsSold: 0, voidCount: 0
        )
        XCTAssertFalse(s.requiresManagerSignOff, "Exactly $2.00 short should NOT require sign-off")
    }

    func test_201CentsDeltaRequiresSignOff() {
        let s = EndShiftSummary(
            salesCount: 0, grossCents: 0, tipsCents: 0,
            cashExpectedCents: 201, cashCountedCents: 0,
            itemsSold: 0, voidCount: 0
        )
        XCTAssertTrue(s.requiresManagerSignOff, "$2.01 short should require sign-off")
    }

    // MARK: - overShortLabel

    func test_overLabelHasPlusPrefix() {
        let s = EndShiftSummary(
            salesCount: 0, grossCents: 0, tipsCents: 0,
            cashExpectedCents: 0, cashCountedCents: 250,
            itemsSold: 0, voidCount: 0
        )
        XCTAssertTrue(s.overShortLabel.hasPrefix("+"))
        XCTAssertTrue(s.overShortLabel.contains("over"))
    }

    func test_shortLabelHasMinusPrefix() {
        let s = EndShiftSummary(
            salesCount: 0, grossCents: 0, tipsCents: 0,
            cashExpectedCents: 250, cashCountedCents: 0,
            itemsSold: 0, voidCount: 0
        )
        XCTAssertTrue(s.overShortLabel.hasPrefix("-"))
        XCTAssertTrue(s.overShortLabel.contains("short"))
    }

    // MARK: - CashDenomination

    func test_denominationTotalCentsMatchesLabelMultipliedByCount() {
        var denom = CashDenomination(id: 2000, label: "$20")
        denom.count = 3
        XCTAssertEqual(denom.totalCents, 6000)
    }

    func test_defaultDenominationsContains11Items() {
        XCTAssertEqual(CashDenomination.defaultDenominations.count, 11)
    }

    func test_allDenominationsAtCount1Sum() {
        let denoms = CashDenomination.defaultDenominations.map { d -> CashDenomination in
            var m = d; m.count = 1; return m
        }
        let total = denoms.reduce(0) { $0 + $1.totalCents }
        // 10000+5000+2000+1000+500+200+100+25+10+5+1 = 18841
        XCTAssertEqual(total, 18841)
    }
}
