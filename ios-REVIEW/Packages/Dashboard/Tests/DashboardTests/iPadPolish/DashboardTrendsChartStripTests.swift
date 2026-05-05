import XCTest
@testable import Dashboard
import Networking

// MARK: - DashboardTrendsChartStripTests
//
// Tests for:
//   • `ChartPeriod.sampleCount`  — correct data-point count per period
//   • `buildTrendData(from:period:)` — data shaping correctness
//   • `trendJitter(index:count:)`    — determinism & bounds
//
// All tests are pure logic; no SwiftUI / Charts rendering required.
// Coverage target: ≥ 80% of DashboardTrendsChartStrip.swift helpers.

final class DashboardTrendsChartStripTests: XCTestCase {

    // MARK: - ChartPeriod.sampleCount

    func test_period_h24_sampleCount() {
        XCTAssertEqual(ChartPeriod.h24.sampleCount, 24)
    }

    func test_period_d7_sampleCount() {
        XCTAssertEqual(ChartPeriod.d7.sampleCount, 7)
    }

    func test_period_d30_sampleCount() {
        XCTAssertEqual(ChartPeriod.d30.sampleCount, 30)
    }

    // MARK: - ChartPeriod: identifiers and labels

    func test_period_ids_matchRawValues() {
        for period in ChartPeriod.allCases {
            XCTAssertEqual(period.id, period.rawValue)
        }
    }

    func test_period_labels_matchRawValues() {
        for period in ChartPeriod.allCases {
            XCTAssertEqual(period.label, period.rawValue)
        }
    }

    // MARK: - buildTrendData: count

    func test_buildTrendData_h24_producesCorrectCount() {
        let data = buildTrendData(from: .init(), period: .h24)
        XCTAssertEqual(data.count, 24)
    }

    func test_buildTrendData_d7_producesCorrectCount() {
        let data = buildTrendData(from: .init(), period: .d7)
        XCTAssertEqual(data.count, 7)
    }

    func test_buildTrendData_d30_producesCorrectCount() {
        let data = buildTrendData(from: .init(), period: .d30)
        XCTAssertEqual(data.count, 30)
    }

    // MARK: - buildTrendData: indices

    func test_buildTrendData_indices_areContiguous() {
        let data = buildTrendData(from: .init(), period: .d7)
        let indices = data.map(\.index)
        XCTAssertEqual(indices, Array(0..<7), "Indices must be 0-based and contiguous")
    }

    // MARK: - buildTrendData: anchor at last point

    func test_buildTrendData_lastPoint_revenueIsNonNegative() {
        let summary = DashboardSummary(revenueToday: 500)
        let data = buildTrendData(from: summary, period: .d7)
        let last = data.last!
        XCTAssertGreaterThan(last.revenue, 0)
    }

    func test_buildTrendData_allRevenues_areNonNegative() {
        let summary = DashboardSummary(revenueToday: 0)
        let data = buildTrendData(from: summary, period: .d30)
        for point in data {
            XCTAssertGreaterThanOrEqual(point.revenue, 0,
                "Revenue at index \(point.index) must not be negative")
        }
    }

    func test_buildTrendData_allClosed_areNonNegative() {
        let summary = DashboardSummary(closedToday: 0)
        let data = buildTrendData(from: summary, period: .d30)
        for point in data {
            XCTAssertGreaterThanOrEqual(point.closed, 0,
                "Closed count at index \(point.index) must not be negative")
        }
    }

    func test_buildTrendData_allNewTickets_areNonNegative() {
        let summary = DashboardSummary(ticketsCreatedToday: 0)
        let data = buildTrendData(from: summary, period: .d30)
        for point in data {
            XCTAssertGreaterThanOrEqual(point.newTickets, 0,
                "New tickets at index \(point.index) must not be negative")
        }
    }

    // MARK: - buildTrendData: scaling proportional to anchor

    func test_buildTrendData_higherRevenueSummary_producesHigherValues() {
        let lowSummary  = DashboardSummary(revenueToday: 100)
        let highSummary = DashboardSummary(revenueToday: 10_000)
        let lowData  = buildTrendData(from: lowSummary,  period: .d7)
        let highData = buildTrendData(from: highSummary, period: .d7)
        let lowMax  = lowData.map(\.revenue).max() ?? 0
        let highMax = highData.map(\.revenue).max() ?? 0
        XCTAssertGreaterThan(highMax, lowMax,
            "Higher anchor revenue must produce proportionally higher chart values")
    }

    // MARK: - buildTrendData: determinism

    func test_buildTrendData_sameSummary_sameResults() {
        let summary = DashboardSummary(openTickets: 3, revenueToday: 800, closedToday: 2)
        let first  = buildTrendData(from: summary, period: .d7)
        let second = buildTrendData(from: summary, period: .d7)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.revenue, b.revenue,
                "buildTrendData must be deterministic for the same summary + period")
            XCTAssertEqual(a.closed, b.closed)
            XCTAssertEqual(a.newTickets, b.newTickets)
        }
    }

    // MARK: - buildTrendData: unique IDs

    func test_buildTrendData_idsAreUnique() {
        let data = buildTrendData(from: .init(), period: .d30)
        let ids = Set(data.map(\.id))
        XCTAssertEqual(ids.count, data.count, "Every data point must have a unique ID")
    }

    // MARK: - trendJitter: bounds

    func test_jitter_isAlwaysInRange_0_75_to_1_25() {
        for count in [7, 24, 30] {
            for index in 0..<count {
                let j = trendJitter(index: index, count: count)
                XCTAssertGreaterThanOrEqual(j, 0.75,
                    "Jitter at index \(index)/\(count) must be ≥ 0.75 but was \(j)")
                XCTAssertLessThanOrEqual(j, 1.25,
                    "Jitter at index \(index)/\(count) must be ≤ 1.25 but was \(j)")
            }
        }
    }

    func test_jitter_isDeterministic_for_sameInputs() {
        let j1 = trendJitter(index: 3, count: 7)
        let j2 = trendJitter(index: 3, count: 7)
        XCTAssertEqual(j1, j2, "trendJitter must be deterministic")
    }

    func test_jitter_differsByIndex() {
        // Not all jitter values should be identical — that would be degenerate.
        let values = (0..<7).map { trendJitter(index: $0, count: 7) }
        let unique = Set(values)
        XCTAssertGreaterThan(unique.count, 1,
            "Jitter values across indices should not all be the same")
    }

    // MARK: - ChartPeriod CaseIterable

    func test_period_allCases_count() {
        XCTAssertEqual(ChartPeriod.allCases.count, 3)
    }

    func test_period_allCases_rawValues() {
        let raws = ChartPeriod.allCases.map(\.rawValue)
        XCTAssertEqual(raws, ["24h", "7d", "30d"])
    }

    // MARK: - ChartMetric CaseIterable

    func test_metric_allCases_count() {
        XCTAssertEqual(ChartMetric.allCases.count, 3)
    }

    func test_metric_ids_matchRawValues() {
        for m in ChartMetric.allCases {
            XCTAssertEqual(m.id, m.rawValue)
        }
    }
}
