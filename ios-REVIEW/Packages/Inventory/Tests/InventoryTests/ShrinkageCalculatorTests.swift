import XCTest
@testable import Inventory

final class ShrinkageCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private func point(
        period: String = "2026-01",
        expected: Int,
        actual: Int,
        reason: ShrinkageReason = .damage,
        costCents: Int = 1000
    ) -> ShrinkagePoint {
        // Use the memberwise init via the Decodable struct
        let json = """
        {
          "period": "\(period)",
          "expected_qty": \(expected),
          "actual_qty": \(actual),
          "reason": "\(reason.rawValue)",
          "cost_cents": \(costCents)
        }
        """
        return try! JSONDecoder().decode(ShrinkagePoint.self, from: json.data(using: .utf8)!)
    }

    // MARK: - Summary tests

    func test_summary_noLoss_zeroCounts() {
        let points = [point(expected: 100, actual: 100)]
        let s = ShrinkageCalculator.summary(from: points)
        XCTAssertEqual(s.totalUnitsLost, 0)
        XCTAssertEqual(s.totalCostCents, 0)
        XCTAssertEqual(s.shrinkagePct, 0)
    }

    func test_summary_loss_countsCorrectly() {
        let points = [
            point(period: "2026-01", expected: 100, actual: 90, costCents: 500),
            point(period: "2026-02", expected: 200, actual: 195, costCents: 250)
        ]
        let s = ShrinkageCalculator.summary(from: points)
        XCTAssertEqual(s.totalUnitsLost, 15)
        XCTAssertEqual(s.totalCostCents, 750)
    }

    func test_summary_shrinkagePct_calculatedCorrectly() {
        // 10 lost out of 100 expected = 10%
        let points = [point(expected: 100, actual: 90, costCents: 0)]
        let s = ShrinkageCalculator.summary(from: points)
        XCTAssertEqual(s.shrinkagePct, 10.0, accuracy: 0.01)
    }

    func test_summary_emptyPoints_zeroSummary() {
        let s = ShrinkageCalculator.summary(from: [])
        XCTAssertEqual(s.totalUnitsLost, 0)
        XCTAssertEqual(s.shrinkagePct, 0)
    }

    // MARK: - By reason tests

    func test_byReason_onlyLossesGrouped() {
        let points = [
            point(expected: 100, actual: 90, reason: .theft, costCents: 1000),
            point(expected: 50, actual: 50, reason: .damage, costCents: 0),
            point(expected: 30, actual: 25, reason: .theft, costCents: 500)
        ]
        let grouped = ShrinkageCalculator.byReason(from: points)
        let theftEntry = grouped.first { $0.0 == .theft }
        XCTAssertNotNil(theftEntry)
        XCTAssertEqual(theftEntry?.1, 15) // 10 + 5
    }

    func test_byReason_noLoss_returnsNoEntries() {
        let points = [point(expected: 100, actual: 100)]
        let grouped = ShrinkageCalculator.byReason(from: points)
        XCTAssertTrue(grouped.isEmpty)
    }

    func test_byReason_damageAndExpiry_bothPresent() {
        let points = [
            point(expected: 100, actual: 95, reason: .damage),
            point(expected: 100, actual: 97, reason: .expiry)
        ]
        let grouped = ShrinkageCalculator.byReason(from: points)
        XCTAssertEqual(grouped.count, 2)
    }

    // MARK: - Cost formatted

    func test_summary_costFormatted_dollarsAndCents() {
        let points = [point(expected: 100, actual: 80, costCents: 2550)]
        let s = ShrinkageCalculator.summary(from: points)
        XCTAssertEqual(s.costFormatted, "$25.50")
    }
}
