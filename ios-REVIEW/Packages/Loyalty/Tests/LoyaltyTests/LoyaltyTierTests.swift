import XCTest
@testable import Loyalty

/// §38 — `LoyaltyTier` unit tests.
/// Covers comparable ordering, raw-value round-trip, parse helper, and display properties.
final class LoyaltyTierTests: XCTestCase {

    // MARK: - Comparable ordering

    func test_bronze_lessThan_silver() {
        XCTAssertTrue(LoyaltyTier.bronze < LoyaltyTier.silver)
    }

    func test_silver_lessThan_gold() {
        XCTAssertTrue(LoyaltyTier.silver < LoyaltyTier.gold)
    }

    func test_gold_lessThan_platinum() {
        XCTAssertTrue(LoyaltyTier.gold < LoyaltyTier.platinum)
    }

    func test_bronze_lessThan_platinum() {
        XCTAssertTrue(LoyaltyTier.bronze < LoyaltyTier.platinum)
    }

    func test_platinum_notLessThan_bronze() {
        XCTAssertFalse(LoyaltyTier.platinum < LoyaltyTier.bronze)
    }

    func test_equal_tiers_notLessThan() {
        XCTAssertFalse(LoyaltyTier.gold < LoyaltyTier.gold)
    }

    func test_allCases_ascending() {
        let ordered = LoyaltyTier.allCases.sorted()
        XCTAssertEqual(ordered, [.bronze, .silver, .gold, .platinum])
    }

    // MARK: - Raw value decode

    func test_rawValue_bronze() {
        XCTAssertEqual(LoyaltyTier(rawValue: "bronze"), .bronze)
    }

    func test_rawValue_silver() {
        XCTAssertEqual(LoyaltyTier(rawValue: "silver"), .silver)
    }

    func test_rawValue_gold() {
        XCTAssertEqual(LoyaltyTier(rawValue: "gold"), .gold)
    }

    func test_rawValue_platinum() {
        XCTAssertEqual(LoyaltyTier(rawValue: "platinum"), .platinum)
    }

    func test_rawValue_unknown_returnsNil() {
        XCTAssertNil(LoyaltyTier(rawValue: "diamond"))
    }

    // MARK: - parse helper

    func test_parse_lowercase() {
        XCTAssertEqual(LoyaltyTier.parse("gold"), .gold)
    }

    func test_parse_uppercase_caseInsensitive() {
        XCTAssertEqual(LoyaltyTier.parse("SILVER"), .silver)
    }

    func test_parse_mixed_case() {
        XCTAssertEqual(LoyaltyTier.parse("Platinum"), .platinum)
    }

    func test_parse_unknown_defaults_to_bronze() {
        XCTAssertEqual(LoyaltyTier.parse("vip"), .bronze)
    }

    func test_parse_empty_defaults_to_bronze() {
        XCTAssertEqual(LoyaltyTier.parse(""), .bronze)
    }

    // MARK: - Display

    func test_displayName_bronze() {
        XCTAssertEqual(LoyaltyTier.bronze.displayName, "Bronze")
    }

    func test_displayName_silver() {
        XCTAssertEqual(LoyaltyTier.silver.displayName, "Silver")
    }

    func test_displayName_gold() {
        XCTAssertEqual(LoyaltyTier.gold.displayName, "Gold")
    }

    func test_displayName_platinum() {
        XCTAssertEqual(LoyaltyTier.platinum.displayName, "Platinum")
    }
}
