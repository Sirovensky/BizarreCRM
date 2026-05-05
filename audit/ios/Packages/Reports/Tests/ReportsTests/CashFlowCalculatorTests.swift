import XCTest
@testable import Reports

final class CashFlowCalculatorTests: XCTestCase {

    // MARK: - buildSeries (day granularity)

    func test_buildSeries_empty_returnsEmpty() {
        let series = CashFlowCalculator.buildSeries(inflows: [], outflows: [])
        XCTAssertTrue(series.isEmpty)
    }

    func test_buildSeries_inflowsOnly() {
        let date = makeDate(year: 2025, month: 1, day: 15)
        let series = CashFlowCalculator.buildSeries(
            inflows: [(date: date, amountCents: 10000)],
            outflows: []
        )
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.inflowCents, 10000)
        XCTAssertEqual(series.first?.outflowCents, 0)
    }

    func test_buildSeries_outflowsOnly() {
        let date = makeDate(year: 2025, month: 2, day: 10)
        let series = CashFlowCalculator.buildSeries(
            inflows: [],
            outflows: [(date: date, amountCents: 5000)]
        )
        XCTAssertEqual(series.first?.outflowCents, 5000)
        XCTAssertEqual(series.first?.inflowCents, 0)
    }

    func test_buildSeries_sameDayBucketsAreMerged() {
        let date = makeDate(year: 2025, month: 3, day: 5)
        let series = CashFlowCalculator.buildSeries(
            inflows: [
                (date: date, amountCents: 3000),
                (date: date, amountCents: 2000)
            ],
            outflows: [(date: date, amountCents: 1000)]
        )
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series.first?.inflowCents, 5000)
        XCTAssertEqual(series.first?.outflowCents, 1000)
    }

    func test_buildSeries_differentDaysProduceMultiplePoints() {
        let d1 = makeDate(year: 2025, month: 4, day: 1)
        let d2 = makeDate(year: 2025, month: 4, day: 2)
        let series = CashFlowCalculator.buildSeries(
            inflows: [(date: d1, amountCents: 1000), (date: d2, amountCents: 2000)],
            outflows: []
        )
        XCTAssertEqual(series.count, 2)
    }

    func test_buildSeries_sortedByDateAscending() {
        let d1 = makeDate(year: 2025, month: 6, day: 10)
        let d2 = makeDate(year: 2025, month: 6, day: 5)  // Earlier
        let series = CashFlowCalculator.buildSeries(
            inflows: [(date: d1, amountCents: 1000), (date: d2, amountCents: 2000)],
            outflows: []
        )
        // Should be sorted oldest-first: June 5, then June 10
        XCTAssertEqual(series.count, 2)
        let first = series[0]
        let second = series[1]
        XCTAssertLessThanOrEqual(first.date, second.date)
    }

    // MARK: - netCents

    func test_netCents_inflowMinusOutflow() {
        let point = CashFlowPoint(id: "x", date: Date(), inflowCents: 5000, outflowCents: 2000)
        XCTAssertEqual(point.netCents, 3000)
    }

    func test_netCents_negative() {
        let point = CashFlowPoint(id: "x", date: Date(), inflowCents: 1000, outflowCents: 4000)
        XCTAssertEqual(point.netCents, -3000)
    }

    // MARK: - cumulativeNet

    func test_cumulativeNet_empty() {
        let cum = CashFlowCalculator.cumulativeNet(series: [])
        XCTAssertTrue(cum.isEmpty)
    }

    func test_cumulativeNet_singlePoint() {
        let point = CashFlowPoint(id: "a", date: Date(), inflowCents: 10000, outflowCents: 4000)
        let cum = CashFlowCalculator.cumulativeNet(series: [point])
        XCTAssertEqual(cum.count, 1)
        // Net = 6000; cumulative inflow = 6000 + outflow = 10000 — original inflow preserved by formula
        XCTAssertEqual(cum.first?.outflowCents, 4000) // outflow unchanged
    }

    // MARK: - Monthly grouping

    func test_buildSeries_monthGrouping() {
        let jan1  = makeDate(year: 2025, month: 1, day: 1)
        let jan15 = makeDate(year: 2025, month: 1, day: 15)
        let feb1  = makeDate(year: 2025, month: 2, day: 1)
        let series = CashFlowCalculator.buildSeries(
            inflows: [
                (date: jan1,  amountCents: 5000),
                (date: jan15, amountCents: 3000),
                (date: feb1,  amountCents: 7000)
            ],
            outflows: [],
            groupBy: .month
        )
        XCTAssertEqual(series.count, 2)
        let jan = series.first
        XCTAssertEqual(jan?.inflowCents, 8000) // 5000 + 3000
        let feb = series.last
        XCTAssertEqual(feb?.inflowCents, 7000)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        return Calendar.current.date(from: comps) ?? Date()
    }
}
