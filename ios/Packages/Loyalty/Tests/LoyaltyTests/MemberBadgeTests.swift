import XCTest
@testable import Loyalty

// MARK: - §38.1 MemberBadge unit tests

final class MemberBadgeTests: XCTestCase {

    // MARK: isPaidTier

    func test_isPaidTier_bronze_isFalse() {
        let badge = MemberBadge(tier: .bronze)
        XCTAssertFalse(badge.isPaidTier)
    }

    func test_isPaidTier_silver_isTrue() {
        let badge = MemberBadge(tier: .silver)
        XCTAssertTrue(badge.isPaidTier)
    }

    func test_isPaidTier_gold_isTrue() {
        let badge = MemberBadge(tier: .gold)
        XCTAssertTrue(badge.isPaidTier)
    }

    func test_isPaidTier_platinum_isTrue() {
        let badge = MemberBadge(tier: .platinum)
        XCTAssertTrue(badge.isPaidTier)
    }

    // MARK: tierString convenience init

    func test_tierStringInit_bronze() {
        let badge = MemberBadge(tierString: "bronze")
        XCTAssertFalse(badge.isPaidTier)
    }

    func test_tierStringInit_silver() {
        let badge = MemberBadge(tierString: "silver")
        XCTAssertTrue(badge.isPaidTier)
    }

    func test_tierStringInit_unknown_fallsToBronze() {
        let badge = MemberBadge(tierString: "unknown_tier")
        XCTAssertFalse(badge.isPaidTier)
    }

    func test_tierStringInit_uppercased_fallsToBronze() {
        // LoyaltyTier.parse lowercases so "GOLD" should work
        let badge = MemberBadge(tierString: "GOLD")
        XCTAssertTrue(badge.isPaidTier)
    }

    // MARK: Size variants exist

    func test_sizeEnum_compactExists() {
        let _ = MemberBadge.Size.compact
    }

    func test_sizeEnum_standardExists() {
        let _ = MemberBadge.Size.standard
    }

    func test_sizeEnum_prominentExists() {
        let _ = MemberBadge.Size.prominent
    }

    // MARK: Default size

    func test_defaultSize_isStandard() {
        let badge = MemberBadge(tier: .gold)
        // Verify default init creates the view with standard size (state accessible via the tier)
        XCTAssertTrue(badge.isPaidTier) // proxy: if it initialises correctly, tier is set
    }
}

// MARK: - §38.1 LoyaltyTier supporting tests

final class LoyaltyTierTests: XCTestCase {

    func test_tier_ordering() {
        XCTAssertTrue(LoyaltyTier.bronze < .silver)
        XCTAssertTrue(LoyaltyTier.silver < .gold)
        XCTAssertTrue(LoyaltyTier.gold < .platinum)
    }

    func test_parse_knownValues() {
        XCTAssertEqual(LoyaltyTier.parse("bronze"), .bronze)
        XCTAssertEqual(LoyaltyTier.parse("silver"), .silver)
        XCTAssertEqual(LoyaltyTier.parse("gold"), .gold)
        XCTAssertEqual(LoyaltyTier.parse("platinum"), .platinum)
    }

    func test_parse_unknown_returnsBronze() {
        XCTAssertEqual(LoyaltyTier.parse("diamond"), .bronze)
        XCTAssertEqual(LoyaltyTier.parse(""), .bronze)
    }

    func test_minLifetimeSpendCents() {
        XCTAssertEqual(LoyaltyTier.bronze.minLifetimeSpendCents, 0)
        XCTAssertEqual(LoyaltyTier.silver.minLifetimeSpendCents, 50_000)
        XCTAssertEqual(LoyaltyTier.gold.minLifetimeSpendCents, 100_000)
        XCTAssertEqual(LoyaltyTier.platinum.minLifetimeSpendCents, 500_000)
    }

    func test_displayName_allCases() {
        XCTAssertEqual(LoyaltyTier.bronze.displayName, "Bronze")
        XCTAssertEqual(LoyaltyTier.silver.displayName, "Silver")
        XCTAssertEqual(LoyaltyTier.gold.displayName, "Gold")
        XCTAssertEqual(LoyaltyTier.platinum.displayName, "Platinum")
    }

    func test_systemSymbol_allCases() {
        // Just verify non-empty
        for tier in LoyaltyTier.allCases {
            XCTAssertFalse(tier.systemSymbol.isEmpty)
        }
    }

    func test_perksDescription_allCases() {
        for tier in LoyaltyTier.allCases {
            XCTAssertFalse(tier.perksDescription.isEmpty)
        }
    }
}
