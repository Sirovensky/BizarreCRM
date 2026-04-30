import XCTest
@testable import Reports

// MARK: - DataIntegrity§91_12Tests
//
// Tests for §91.12 data-integrity guards across dashboard cards.
// Covers: RevenueCardContext enum, AvgTicketValueCard inconsistency chip,
// TicketsByStatusCard.hidesWhenAllZero, NPSScore.hasEnoughData,
// and InventoryMovementCard.stockHealthWarning.

final class DataIntegrity§91_12Tests: XCTestCase {

    // MARK: 1. RevenueCardContext enum cases compile

    func test_revenueCardContext_allCasesPresent() {
        // All three cases declared in §91.12 must be reachable.
        let all = RevenueCardContext.allCases
        XCTAssertTrue(all.contains(.sales),     "Expected .sales case")
        XCTAssertTrue(all.contains(.inventory), "Expected .inventory case")
        XCTAssertTrue(all.contains(.hidden),    "Expected .hidden case")
        XCTAssertEqual(all.count, 3, "Expected exactly 3 RevenueCardContext cases")
    }

    // MARK: 2. AvgTicketValueCard shows inconsistent chip when revenue > 0 && ticketCount == 0

    func test_avgTicketValueCard_isDataInconsistent_whenRevenuePositiveAndTicketCountZero() {
        let card = AvgTicketValueCard(value: nil, revenue: 500.0, ticketCount: 0)
        XCTAssertTrue(
            card.isDataInconsistent,
            "Card must flag inconsistency when revenue > 0 and ticketCount == 0"
        )
    }

    // MARK: 3. AvgTicketValueCard does NOT show chip when ticketCount > 0

    func test_avgTicketValueCard_isDataInconsistent_falseWhenTicketCountPositive() {
        let card = AvgTicketValueCard(value: nil, revenue: 500.0, ticketCount: 12)
        XCTAssertFalse(
            card.isDataInconsistent,
            "Card must NOT flag inconsistency when ticketCount > 0"
        )
    }

    func test_avgTicketValueCard_isDataInconsistent_falseWhenBothZero() {
        // revenue == 0 && ticketCount == 0 is not an inconsistency — just no data.
        let card = AvgTicketValueCard(value: nil, revenue: 0, ticketCount: 0)
        XCTAssertFalse(
            card.isDataInconsistent,
            "Card must NOT flag inconsistency when both revenue and ticketCount are zero"
        )
    }

    // MARK: 4. TicketsByStatusCard.hidesWhenAllZero + all zero counts → allCountsAreZero

    func test_ticketsByStatusCard_allCountsAreZero_trueWhenAllZero() {
        let zeroCounts = [
            TicketStatusPoint(id: 1, status: "Open",   count: 0),
            TicketStatusPoint(id: 2, status: "Closed", count: 0),
            TicketStatusPoint(id: 3, status: "Pending", count: 0),
        ]
        let card = TicketsByStatusCard(points: zeroCounts, hidesWhenAllZero: true)
        XCTAssertTrue(
            card.allCountsAreZero,
            "allCountsAreZero must be true when every status point has count == 0"
        )
        XCTAssertTrue(
            card.hidesWhenAllZero,
            "hidesWhenAllZero must be true as passed"
        )
    }

    func test_ticketsByStatusCard_allCountsAreZero_falseWhenSomeNonZero() {
        let mixed = [
            TicketStatusPoint(id: 1, status: "Open",   count: 0),
            TicketStatusPoint(id: 2, status: "Closed", count: 7),
        ]
        let card = TicketsByStatusCard(points: mixed, hidesWhenAllZero: true)
        XCTAssertFalse(
            card.allCountsAreZero,
            "allCountsAreZero must be false when at least one count is non-zero"
        )
    }

    // MARK: 5. NPSScore.hasEnoughData returns false when respondentCount < 10

    func test_npsScore_hasEnoughData_falseWhenRespondentCountBelowThreshold() {
        let score = NPSScore(
            current: 42, previous: 35,
            promoterPct: 60, detractorPct: 20,
            themes: [], respondentCount: 9
        )
        XCTAssertFalse(
            score.hasEnoughData,
            "hasEnoughData must be false when respondentCount (9) < 10"
        )
    }

    func test_npsScore_hasEnoughData_falseWhenRespondentCountIsNil() {
        let score = NPSScore(
            current: 42, previous: 35,
            promoterPct: 60, detractorPct: 20,
            themes: [], respondentCount: nil
        )
        XCTAssertFalse(
            score.hasEnoughData,
            "hasEnoughData must be false when respondentCount is nil"
        )
    }

    // MARK: 6. NPSScore.hasEnoughData returns true when respondentCount >= 10

    func test_npsScore_hasEnoughData_trueAtExactThreshold() {
        let score = NPSScore(
            current: 42, previous: 35,
            promoterPct: 60, detractorPct: 20,
            themes: [], respondentCount: 10
        )
        XCTAssertTrue(
            score.hasEnoughData,
            "hasEnoughData must be true when respondentCount == 10 (boundary)"
        )
    }

    func test_npsScore_hasEnoughData_trueWhenRespondentCountAboveThreshold() {
        let score = NPSScore(
            current: 55, previous: 48,
            promoterPct: 70, detractorPct: 10,
            themes: ["Quality", "Speed"], respondentCount: 250
        )
        XCTAssertTrue(
            score.hasEnoughData,
            "hasEnoughData must be true when respondentCount (250) >= 10"
        )
    }

    // MARK: 7. InventoryMovementCard.stockHealthWarning

    func test_inventoryMovementCard_stockHealthWarning_trueWhenOOSPositiveAndValueZero() {
        let report = InventoryReport(
            outOfStockCount: 3,
            lowStockCount: 0,
            valueSummary: [
                InventoryValueEntry(
                    itemType: "parts", itemCount: 10,
                    totalUnits: 10, totalCostValue: 0, totalRetailValue: 0
                )
            ],
            topMoving: []
        )
        let card = InventoryMovementCard(report: report)
        XCTAssertTrue(
            card.stockHealthWarning,
            "stockHealthWarning must be true when OOS > 0 and total retail value == 0"
        )
    }

    func test_inventoryMovementCard_stockHealthWarning_falseWhenValueIsPositive() {
        let report = InventoryReport(
            outOfStockCount: 2,
            lowStockCount: 0,
            valueSummary: [
                InventoryValueEntry(
                    itemType: "parts", itemCount: 10,
                    totalUnits: 10, totalCostValue: 200, totalRetailValue: 450
                )
            ],
            topMoving: []
        )
        let card = InventoryMovementCard(report: report)
        XCTAssertFalse(
            card.stockHealthWarning,
            "stockHealthWarning must be false when total retail value > 0"
        )
    }

    func test_inventoryMovementCard_stockHealthWarning_falseWhenOOSIsZero() {
        let report = InventoryReport(
            outOfStockCount: 0,
            lowStockCount: 1,
            valueSummary: [],
            topMoving: []
        )
        let card = InventoryMovementCard(report: report)
        XCTAssertFalse(
            card.stockHealthWarning,
            "stockHealthWarning must be false when outOfStockCount == 0"
        )
    }
}
