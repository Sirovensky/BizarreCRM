import XCTest
@testable import Customers

// MARK: - LTVPerkApplierTests
// §44.2 — Tests for LTVPerkApplier.applicablePerks(tier:perks:).

final class LTVPerkApplierTests: XCTestCase {

    // MARK: Filtering by tier

    func test_applicablePerks_returnsOnlyMatchingTier() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "1", tier: .bronze, kind: .discount(percent: 5), description: "5% off"),
            LTVPerk(id: "2", tier: .silver, kind: .discount(percent: 10), description: "10% off"),
            LTVPerk(id: "3", tier: .gold, kind: .priorityQueue(position: 1), description: "Priority"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .silver, perks: perks)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "2")
    }

    func test_applicablePerks_emptyWhenNoMatch() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "1", tier: .bronze, kind: .discount(percent: 5), description: "5% off"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .platinum, perks: perks)
        XCTAssertTrue(result.isEmpty)
    }

    func test_applicablePerks_emptyInputReturnsEmpty() {
        let result = LTVPerkApplier.applicablePerks(tier: .gold, perks: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_applicablePerks_multipleSameTier() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "1", tier: .platinum, kind: .discount(percent: 15), description: "15% off"),
            LTVPerk(id: "2", tier: .platinum, kind: .warrantyMonths(3), description: "+3 months"),
            LTVPerk(id: "3", tier: .gold, kind: .discount(percent: 10), description: "10% off"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .platinum, perks: perks)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.tier == .platinum })
    }

    // MARK: Immutability — input unchanged

    func test_applicablePerks_doesNotMutateInput() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "1", tier: .bronze, kind: .discount(percent: 5), description: "5%"),
            LTVPerk(id: "2", tier: .silver, kind: .discount(percent: 10), description: "10%"),
        ]
        let originalCount = perks.count
        _ = LTVPerkApplier.applicablePerks(tier: .silver, perks: perks)
        XCTAssertEqual(perks.count, originalCount)
    }

    // MARK: Perk kinds

    func test_applicablePerks_discountKind() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "d", tier: .gold, kind: .discount(percent: 12), description: "12% off"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .gold, perks: perks)
        if case .discount(let pct) = result.first?.kind {
            XCTAssertEqual(pct, 12)
        } else {
            XCTFail("Expected discount perk")
        }
    }

    func test_applicablePerks_warrantyKind() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "w", tier: .platinum, kind: .warrantyMonths(6), description: "+6 months"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .platinum, perks: perks)
        if case .warrantyMonths(let months) = result.first?.kind {
            XCTAssertEqual(months, 6)
        } else {
            XCTFail("Expected warranty perk")
        }
    }

    func test_applicablePerks_priorityQueueKind() {
        let perks: [LTVPerk] = [
            LTVPerk(id: "p", tier: .silver, kind: .priorityQueue(position: 2), description: "Priority #2"),
        ]
        let result = LTVPerkApplier.applicablePerks(tier: .silver, perks: perks)
        if case .priorityQueue(let pos) = result.first?.kind {
            XCTAssertEqual(pos, 2)
        } else {
            XCTFail("Expected priority queue perk")
        }
    }
}
