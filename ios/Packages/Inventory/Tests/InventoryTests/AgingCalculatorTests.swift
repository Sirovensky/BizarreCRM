import XCTest
@testable import Inventory

final class AgingCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeItem(
        id: Int64, daysInStock: Int, tier: AgingTier = .fresh, inStock: Int = 10
    ) -> AgedItem {
        let json = """
        {
          "id": \(id),
          "sku": "SKU\(id)",
          "name": "Item \(id)",
          "days_in_stock": \(daysInStock),
          "in_stock": \(inStock),
          "retail_cents": 1000,
          "tier": "\(tier.rawValue)"
        }
        """
        return try! JSONDecoder().decode(AgedItem.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Group by tier

    func test_groupByTier_correctCounts() {
        let items = [
            makeItem(id: 1, daysInStock: 10, tier: .fresh),
            makeItem(id: 2, daysInStock: 90, tier: .slow),
            makeItem(id: 3, daysInStock: 200, tier: .dead),
            makeItem(id: 4, daysInStock: 400, tier: .obsolete),
            makeItem(id: 5, daysInStock: 15, tier: .fresh)
        ]
        let grouped = AgingCalculator.groupByTier(items: items)
        let freshCount = grouped.first { $0.0 == .fresh }?.1 ?? 0
        let slowCount = grouped.first { $0.0 == .slow }?.1 ?? 0
        let deadCount = grouped.first { $0.0 == .dead }?.1 ?? 0
        let obsCount = grouped.first { $0.0 == .obsolete }?.1 ?? 0

        XCTAssertEqual(freshCount, 2)
        XCTAssertEqual(slowCount, 1)
        XCTAssertEqual(deadCount, 1)
        XCTAssertEqual(obsCount, 1)
    }

    func test_groupByTier_emptyItems_allZero() {
        let grouped = AgingCalculator.groupByTier(items: [])
        XCTAssertTrue(grouped.allSatisfy { $0.1 == 0 })
    }

    // MARK: - Clearance suggestions

    func test_clearanceSuggestions_onlyDeadAndObsolete() {
        let items = [
            makeItem(id: 1, daysInStock: 10, tier: .fresh),
            makeItem(id: 2, daysInStock: 90, tier: .slow),
            makeItem(id: 3, daysInStock: 200, tier: .dead),
            makeItem(id: 4, daysInStock: 400, tier: .obsolete)
        ]
        let suggestions = AgingCalculator.clearanceSuggestions(for: items)
        XCTAssertEqual(suggestions.count, 2)
        XCTAssertTrue(suggestions.allSatisfy { $0.tier == .dead || $0.tier == .obsolete })
    }

    func test_clearanceSuggestions_sortedByDaysDescending() {
        let items = [
            makeItem(id: 1, daysInStock: 200, tier: .dead),
            makeItem(id: 2, daysInStock: 400, tier: .obsolete),
            makeItem(id: 3, daysInStock: 250, tier: .dead)
        ]
        let suggestions = AgingCalculator.clearanceSuggestions(for: items)
        XCTAssertEqual(suggestions.first?.id, 2)  // 400d is most aged
        XCTAssertEqual(suggestions.last?.id, 1)   // 200d is least aged
    }

    func test_clearanceSuggestions_noDeadStock_returnsEmpty() {
        let items = [
            makeItem(id: 1, daysInStock: 10, tier: .fresh),
            makeItem(id: 2, daysInStock: 90, tier: .slow)
        ]
        let suggestions = AgingCalculator.clearanceSuggestions(for: items)
        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - AgedItem formatted values

    func test_agedItem_retailFormatted() {
        let item = makeItem(id: 1, daysInStock: 30)
        XCTAssertTrue(item.retailFormatted.hasPrefix("$"))
    }

    func test_agedItem_totalValueFormatted() {
        let item = makeItem(id: 1, daysInStock: 30, inStock: 5)
        XCTAssertTrue(item.totalValueFormatted.hasPrefix("$"))
    }

    // MARK: - AgingTier thresholds

    func test_agingTier_fresh_threshold60() {
        XCTAssertEqual(AgingTier.fresh.daysThreshold, 60)
    }

    func test_agingTier_slow_threshold180() {
        XCTAssertEqual(AgingTier.slow.daysThreshold, 180)
    }

    func test_agingTier_dead_threshold365() {
        XCTAssertEqual(AgingTier.dead.daysThreshold, 365)
    }

    // MARK: - §6.8 deadTier alert

    func test_shouldShowDeadTierAlert_belowMinFleetCount_returnsFalse() {
        // Even at 100% dead, fleets <10 items don't trigger noise.
        let items = (1...5).map { makeItem(id: Int64($0), daysInStock: 200, tier: .dead) }
        XCTAssertFalse(AgingCalculator.shouldShowDeadTierAlert(items: items))
    }

    func test_shouldShowDeadTierAlert_above10Percent_returnsTrue() {
        // 12 items, 3 dead → 25% — above 10% threshold + ≥3 problem items
        var items: [AgedItem] = (1...9).map { makeItem(id: Int64($0), daysInStock: 10, tier: .fresh) }
        items += (10...12).map { makeItem(id: Int64($0), daysInStock: 200, tier: .dead) }
        XCTAssertTrue(AgingCalculator.shouldShowDeadTierAlert(items: items))
    }

    func test_shouldShowDeadTierAlert_under3ProblemItems_returnsFalse() {
        // 20 items, 2 dead — fraction is high enough but problem-count gate fails.
        var items: [AgedItem] = (1...18).map { makeItem(id: Int64($0), daysInStock: 10, tier: .fresh) }
        items += (19...20).map { makeItem(id: Int64($0), daysInStock: 200, tier: .dead) }
        XCTAssertFalse(AgingCalculator.shouldShowDeadTierAlert(items: items))
    }

    // MARK: - §6.8 hot-seller + bundle suggestion text

    func test_hotSeller_picksFreshestWithStock() {
        let items = [
            makeItem(id: 1, daysInStock: 50, tier: .fresh, inStock: 5),
            makeItem(id: 2, daysInStock: 5, tier: .fresh, inStock: 0),   // out of stock — skip
            makeItem(id: 3, daysInStock: 10, tier: .fresh, inStock: 4),  // winner
            makeItem(id: 4, daysInStock: 200, tier: .dead, inStock: 1)
        ]
        XCTAssertEqual(AgingCalculator.hotSeller(in: items)?.id, 3)
    }

    func test_hotSeller_returnsNilWhenNoFreshStock() {
        let items = [makeItem(id: 1, daysInStock: 200, tier: .dead, inStock: 5)]
        XCTAssertNil(AgingCalculator.hotSeller(in: items))
    }

    func test_bundleSuggestionText_fallsBackWhenNoHotSeller() {
        let item = makeItem(id: 1, daysInStock: 200, tier: .dead)
        let text = AgingCalculator.bundleSuggestionText(for: item, hotSeller: nil)
        XCTAssertTrue(text.contains("top-selling"))
    }

    func test_bundleSuggestionText_namesHotSeller() {
        let item = makeItem(id: 1, daysInStock: 200, tier: .dead)
        let hot = makeItem(id: 99, daysInStock: 5, tier: .fresh, inStock: 10)
        let text = AgingCalculator.bundleSuggestionText(for: item, hotSeller: hot)
        XCTAssertTrue(text.contains("Item 99"))
    }

    func test_bundleSuggestionText_skipsHotSellerSameAsItem() {
        // Defensive — if same id, fall back to generic copy.
        let item = makeItem(id: 1, daysInStock: 200, tier: .dead)
        let text = AgingCalculator.bundleSuggestionText(for: item, hotSeller: item)
        XCTAssertTrue(text.contains("top-selling"))
    }

    // MARK: - §6.8 dismissal persistence

    func test_deadStockAlertDismissal_quarterKey_q1() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 2; comps.day = 15
        let date = calendar.date(from: comps)!
        XCTAssertEqual(DeadStockAlertDismissal.quarterKey(for: date, calendar: calendar), "2026-Q1")
    }

    func test_deadStockAlertDismissal_quarterKey_q4() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 11; comps.day = 1
        let date = calendar.date(from: comps)!
        XCTAssertEqual(DeadStockAlertDismissal.quarterKey(for: date, calendar: calendar), "2026-Q4")
    }
}
