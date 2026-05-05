import XCTest
@testable import Pos

final class ShiftSummaryCalculatorTests: XCTestCase {

    // MARK: - Smoke test

    func test_aggregate_emptyRecords_zeroTotals() {
        let summary = ShiftSummaryCalculator.aggregate(
            records:          [],
            shiftId:          "shift-1",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 5000,
            closingCashCents: 5000
        )
        XCTAssertEqual(summary.saleCount,          0)
        XCTAssertEqual(summary.totalRevenueCents,  0)
        XCTAssertEqual(summary.refundsCents,       0)
        XCTAssertEqual(summary.voidsCents,         0)
        XCTAssertEqual(summary.averageTicketCents, 0)
        XCTAssertTrue(summary.tendersBreakdown.isEmpty)
    }

    // MARK: - Revenue

    func test_aggregate_saleCount_equalsRecordCount() {
        let records = makeSales(revenues: [1000, 2000, 3000])
        let summary = aggregate(records)
        XCTAssertEqual(summary.saleCount, 3)
    }

    func test_aggregate_totalRevenue_sumOfAllSales() {
        let records = makeSales(revenues: [1000, 2000, 3000])
        let summary = aggregate(records)
        XCTAssertEqual(summary.totalRevenueCents, 6000)
    }

    func test_aggregate_averageTicket_dividesTotal() {
        let records = makeSales(revenues: [1000, 2000, 3000])
        let summary = aggregate(records)
        XCTAssertEqual(summary.averageTicketCents, 2000)  // 6000/3
    }

    func test_aggregate_averageTicket_zeroWhenNoSales() {
        let summary = aggregate([])
        XCTAssertEqual(summary.averageTicketCents, 0)
    }

    // MARK: - Refunds & voids

    func test_aggregate_refunds_summed() {
        let records = [
            ShiftSummaryCalculator.SaleRecord(revenueCents: 1000, refundCents: 200),
            ShiftSummaryCalculator.SaleRecord(revenueCents: 500,  refundCents: 100)
        ]
        let summary = aggregate(records)
        XCTAssertEqual(summary.refundsCents, 300)
    }

    func test_aggregate_voids_summed() {
        let records = [
            ShiftSummaryCalculator.SaleRecord(revenueCents: 500, voidCents: 150),
            ShiftSummaryCalculator.SaleRecord(revenueCents: 500, voidCents: 50)
        ]
        let summary = aggregate(records)
        XCTAssertEqual(summary.voidsCents, 200)
    }

    // MARK: - Cash variance

    func test_aggregate_noDrift_whenCashBalances() {
        // opening=5000, cash sale=3000, closing=8000 → drift=0
        let records = [ShiftSummaryCalculator.SaleRecord(revenueCents: 3000, isCashSale: true)]
        let summary = ShiftSummaryCalculator.aggregate(
            records:          records,
            shiftId:          "s1",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 5000,
            closingCashCents: 8000
        )
        XCTAssertEqual(summary.calculatedCashCents, 8000)
        XCTAssertEqual(summary.driftCents, 0)
    }

    func test_aggregate_positiveDrift_whenOverCounted() {
        // opening=5000, cash sale=3000, closing=9000 → drift=+1000
        let records = [ShiftSummaryCalculator.SaleRecord(revenueCents: 3000, isCashSale: true)]
        let summary = ShiftSummaryCalculator.aggregate(
            records:          records,
            shiftId:          "s2",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 5000,
            closingCashCents: 9000
        )
        XCTAssertEqual(summary.driftCents, 1000)
    }

    func test_aggregate_negativeDrift_whenShort() {
        // opening=5000, cash sale=3000, closing=7000 → drift=-1000
        let records = [ShiftSummaryCalculator.SaleRecord(revenueCents: 3000, isCashSale: true)]
        let summary = ShiftSummaryCalculator.aggregate(
            records:          records,
            shiftId:          "s3",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 5000,
            closingCashCents: 7000
        )
        XCTAssertEqual(summary.driftCents, -1000)
    }

    func test_aggregate_nonCashSaleDoesNotAffectCalculatedCash() {
        // card sale doesn't change expected cash
        let records = [ShiftSummaryCalculator.SaleRecord(revenueCents: 5000, isCashSale: false)]
        let summary = ShiftSummaryCalculator.aggregate(
            records:          records,
            shiftId:          "s4",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 2000,
            closingCashCents: 2000
        )
        XCTAssertEqual(summary.calculatedCashCents, 2000)
        XCTAssertEqual(summary.driftCents, 0)
    }

    // MARK: - Tenders breakdown

    func test_aggregate_tendersBreakdown_mergedAcrossSales() {
        let records = [
            ShiftSummaryCalculator.SaleRecord(revenueCents: 1000, tenders: ["Cash": 500, "Card": 500]),
            ShiftSummaryCalculator.SaleRecord(revenueCents: 800,  tenders: ["Cash": 800])
        ]
        let summary = aggregate(records)
        XCTAssertEqual(summary.tendersBreakdown["Cash"], 1300)
        XCTAssertEqual(summary.tendersBreakdown["Card"], 500)
    }

    func test_aggregate_endedAt_stored() {
        let start = Date(timeIntervalSinceNow: -3600)
        let end   = Date()
        let summary = ShiftSummaryCalculator.aggregate(
            records:          [],
            shiftId:          "s5",
            startedAt:        start,
            endedAt:          end,
            cashierId:        1,
            openingCashCents: 0,
            closingCashCents: 0
        )
        XCTAssertEqual(summary.endedAt, end)
    }

    func test_aggregate_shiftIdAndCashierIdPreserved() {
        let summary = ShiftSummaryCalculator.aggregate(
            records:          [],
            shiftId:          "shift-abc",
            startedAt:        Date(),
            cashierId:        99,
            openingCashCents: 0,
            closingCashCents: 0
        )
        XCTAssertEqual(summary.shiftId,   "shift-abc")
        XCTAssertEqual(summary.cashierId, 99)
    }

    // MARK: - Helpers

    private func aggregate(_ records: [ShiftSummaryCalculator.SaleRecord]) -> ShiftSummary {
        ShiftSummaryCalculator.aggregate(
            records:          records,
            shiftId:          "test-shift",
            startedAt:        Date(),
            cashierId:        1,
            openingCashCents: 0,
            closingCashCents: 0
        )
    }

    private func makeSales(revenues: [Int]) -> [ShiftSummaryCalculator.SaleRecord] {
        revenues.map { ShiftSummaryCalculator.SaleRecord(revenueCents: $0) }
    }
}
