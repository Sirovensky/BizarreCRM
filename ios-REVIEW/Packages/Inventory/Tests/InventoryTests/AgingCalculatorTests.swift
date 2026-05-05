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
}
