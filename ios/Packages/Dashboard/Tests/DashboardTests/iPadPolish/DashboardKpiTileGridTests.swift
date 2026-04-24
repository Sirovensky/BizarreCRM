import XCTest
@testable import Dashboard
import Networking

// MARK: - DashboardKpiTileGridTests
//
// Tests for:
//   • `kpiColumnCount(for:)` — container-width → column mapping
//   • `kpiItems(from:)`      — DashboardSummary → KpiTileItem[] shaping
//
// All tests are pure logic; no SwiftUI rendering required.
// Coverage target: ≥ 80% of the helper functions in DashboardKpiTileGrid.swift.

final class DashboardKpiTileGridTests: XCTestCase {

    // MARK: - kpiColumnCount: boundary tests

    func test_columnCount_belowLower_returns3() {
        // width 0 — degenerate but valid (empty container)
        XCTAssertEqual(kpiColumnCount(for: 0), 3)
    }

    func test_columnCount_justBelow480_returns3() {
        XCTAssertEqual(kpiColumnCount(for: 479), 3)
    }

    func test_columnCount_exactly480_returns4() {
        // 480 is the lower boundary of the 4-column range
        XCTAssertEqual(kpiColumnCount(for: 480), 4)
    }

    func test_columnCount_midRange_returns4() {
        XCTAssertEqual(kpiColumnCount(for: 560), 4)
    }

    func test_columnCount_justBelow640_returns4() {
        XCTAssertEqual(kpiColumnCount(for: 639), 4)
    }

    func test_columnCount_exactly640_returns6() {
        // 640 is the lower boundary of the 6-column range
        XCTAssertEqual(kpiColumnCount(for: 640), 6)
    }

    func test_columnCount_largeWidth_returns6() {
        // Full-screen iPad landscape: ~1366 pt
        XCTAssertEqual(kpiColumnCount(for: 1366), 6)
    }

    func test_columnCount_veryNarrow_returns3() {
        // iPhone-size container embedded in an iPad split-view
        XCTAssertEqual(kpiColumnCount(for: 320), 3)
    }

    // MARK: - kpiColumnCount: exhaustive mid-range coverage

    func test_columnCount_range3_spans_0_to_479() {
        for w in stride(from: 0, through: 479, by: 50) {
            XCTAssertEqual(kpiColumnCount(for: CGFloat(w)), 3,
                "Width \(w) should yield 3 columns")
        }
    }

    func test_columnCount_range4_spans_480_to_639() {
        for w in stride(from: 480, through: 639, by: 20) {
            XCTAssertEqual(kpiColumnCount(for: CGFloat(w)), 4,
                "Width \(w) should yield 4 columns")
        }
    }

    func test_columnCount_range6_spans_640_and_above() {
        for w in stride(from: 640, through: 2000, by: 100) {
            XCTAssertEqual(kpiColumnCount(for: CGFloat(w)), 6,
                "Width \(w) should yield 6 columns")
        }
    }

    // MARK: - kpiItems: item count

    func test_kpiItems_returnsExactly6Items() {
        let summary = DashboardSummary()
        let items = kpiItems(from: summary)
        XCTAssertEqual(items.count, 6,
            "Grid should always have 6 KPI tiles")
    }

    // MARK: - kpiItems: label order is stable

    func test_kpiItems_labelOrder_isStable() {
        let summary = DashboardSummary()
        let labels = kpiItems(from: summary).map(\.label)
        XCTAssertEqual(labels, [
            "Open tickets",
            "Revenue today",
            "Closed today",
            "New today",
            "Appointments",
            "Inventory value",
        ])
    }

    // MARK: - kpiItems: numeric values match summary

    func test_kpiItems_openTickets_matchesSummary() {
        let summary = DashboardSummary(openTickets: 42)
        let item = kpiItems(from: summary).first { $0.label == "Open tickets" }
        XCTAssertEqual(item?.value, "42")
    }

    func test_kpiItems_closedToday_matchesSummary() {
        let summary = DashboardSummary(closedToday: 7)
        let item = kpiItems(from: summary).first { $0.label == "Closed today" }
        XCTAssertEqual(item?.value, "7")
    }

    func test_kpiItems_ticketsCreatedToday_matchesSummary() {
        let summary = DashboardSummary(ticketsCreatedToday: 5)
        let item = kpiItems(from: summary).first { $0.label == "New today" }
        XCTAssertEqual(item?.value, "5")
    }

    func test_kpiItems_appointmentsToday_matchesSummary() {
        let summary = DashboardSummary(appointmentsToday: 3)
        let item = kpiItems(from: summary).first { $0.label == "Appointments" }
        XCTAssertEqual(item?.value, "3")
    }

    func test_kpiItems_revenue_isCurrencyFormatted() {
        let summary = DashboardSummary(revenueToday: 1234.0)
        let item = kpiItems(from: summary).first { $0.label == "Revenue today" }
        // Formatted as USD with no cents; "$1,234" in en_US locale.
        // We check prefix/contains because locale may vary in CI.
        let value = item?.value ?? ""
        XCTAssertTrue(value.contains("1") && value.contains("234"),
            "Revenue '\(value)' should contain the number 1234")
    }

    func test_kpiItems_inventoryValue_isCurrencyFormatted() {
        let summary = DashboardSummary(inventoryValue: 50000.0)
        let item = kpiItems(from: summary).first { $0.label == "Inventory value" }
        let value = item?.value ?? ""
        XCTAssertTrue(value.contains("50") && value.contains("000"),
            "Inventory value '\(value)' should contain 50000")
    }

    func test_kpiItems_zeroRevenue_doesNotCrash() {
        let summary = DashboardSummary(revenueToday: 0)
        let item = kpiItems(from: summary).first { $0.label == "Revenue today" }
        XCTAssertNotNil(item?.value, "Zero revenue must still produce a non-nil value string")
    }

    // MARK: - kpiItems: each tile has an icon

    func test_kpiItems_allTilesHaveNonEmptyIcon() {
        let summary = DashboardSummary()
        let items = kpiItems(from: summary)
        for item in items {
            XCTAssertFalse(item.icon.isEmpty, "Tile '\(item.label)' must have an SF Symbol icon")
        }
    }

    // MARK: - kpiItems: unique IDs

    func test_kpiItems_idsAreUnique() {
        let summary = DashboardSummary()
        let items = kpiItems(from: summary)
        let ids = Set(items.map(\.id))
        XCTAssertEqual(ids.count, items.count, "Each KPI tile must have a unique ID")
    }
}
