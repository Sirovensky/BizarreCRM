import XCTest
@testable import Customers

// MARK: - LTVCalculatorTests
// §44.2 — Tests for LTVCalculator.tier(for:) covering all 4 threshold buckets
// and boundary values. All pure / synchronous.

final class LTVCalculatorTests: XCTestCase {

    // MARK: Bronze (< $500 → < 50_000 cents)

    func test_tier_0cents_isBronze() {
        XCTAssertEqual(LTVCalculator.tier(for: 0), .bronze)
    }

    func test_tier_4999cents_isBronze() {
        // $49.99
        XCTAssertEqual(LTVCalculator.tier(for: 4_999), .bronze)
    }

    func test_tier_49999cents_isBronze() {
        // $499.99 — just under silver threshold
        XCTAssertEqual(LTVCalculator.tier(for: 49_999), .bronze)
    }

    // MARK: Silver ($500–$1 500 → 50_000–149_999 cents)

    func test_tier_50000cents_isSilver() {
        // $500.00 — exact lower bound
        XCTAssertEqual(LTVCalculator.tier(for: 50_000), .silver)
    }

    func test_tier_100000cents_isSilver() {
        // $1 000 — mid-silver
        XCTAssertEqual(LTVCalculator.tier(for: 100_000), .silver)
    }

    func test_tier_149999cents_isSilver() {
        // $1 499.99 — just under gold
        XCTAssertEqual(LTVCalculator.tier(for: 149_999), .silver)
    }

    // MARK: Gold ($1 500–$5 000 → 150_000–499_999 cents)

    func test_tier_150000cents_isGold() {
        // $1 500.00 — exact lower bound
        XCTAssertEqual(LTVCalculator.tier(for: 150_000), .gold)
    }

    func test_tier_300000cents_isGold() {
        // $3 000 — mid-gold
        XCTAssertEqual(LTVCalculator.tier(for: 300_000), .gold)
    }

    func test_tier_499999cents_isGold() {
        // $4 999.99 — just under platinum
        XCTAssertEqual(LTVCalculator.tier(for: 499_999), .gold)
    }

    // MARK: Platinum (> $5 000 → ≥ 500_000 cents)

    func test_tier_500000cents_isPlatinum() {
        // $5 000.00 — exact threshold
        XCTAssertEqual(LTVCalculator.tier(for: 500_000), .platinum)
    }

    func test_tier_1000000cents_isPlatinum() {
        // $10 000
        XCTAssertEqual(LTVCalculator.tier(for: 1_000_000), .platinum)
    }

    func test_tier_maxInt_isPlatinum() {
        XCTAssertEqual(LTVCalculator.tier(for: Int.max), .platinum)
    }

    // MARK: Tenant override thresholds

    func test_tier_withCustomThresholds_overridesDefaults() {
        // Custom: silver at 10_000, gold at 30_000, platinum at 60_000
        let thresholds = LTVThresholds(silverCents: 10_000, goldCents: 30_000, platinumCents: 60_000)
        XCTAssertEqual(LTVCalculator.tier(for: 9_999, thresholds: thresholds), .bronze)
        XCTAssertEqual(LTVCalculator.tier(for: 10_000, thresholds: thresholds), .silver)
        XCTAssertEqual(LTVCalculator.tier(for: 29_999, thresholds: thresholds), .silver)
        XCTAssertEqual(LTVCalculator.tier(for: 30_000, thresholds: thresholds), .gold)
        XCTAssertEqual(LTVCalculator.tier(for: 59_999, thresholds: thresholds), .gold)
        XCTAssertEqual(LTVCalculator.tier(for: 60_000, thresholds: thresholds), .platinum)
    }
}
