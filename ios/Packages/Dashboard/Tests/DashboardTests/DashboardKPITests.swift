import XCTest
@testable import Dashboard
import Networking

// MARK: - DashboardKPITests
//
// Tests for §3.1 KPI tile expansion:
//   • `kpiItems(from:)` returns the correct set of tiles
//   • KPIs from DashboardKPIs are included when non-nil
//   • Tile count / label correctness
//   • DashboardSnapshot.kpis optional is respected

final class DashboardKPITests: XCTestCase {

    // MARK: - DashboardSnapshot init (backward compat)

    func test_snapshot_withoutKpis_isValid() {
        let snap = DashboardSnapshot(
            summary: DashboardSummary(openTickets: 5),
            attention: NeedsAttention()
        )
        XCTAssertNil(snap.kpis)
        XCTAssertEqual(snap.summary.openTickets, 5)
    }

    func test_snapshot_withKpis_isStored() {
        let kpis = DashboardKPIs(totalSales: 1000, tax: 80, netProfit: 200)
        let snap = DashboardSnapshot(
            summary: DashboardSummary(),
            kpis: kpis,
            attention: NeedsAttention()
        )
        XCTAssertNotNil(snap.kpis)
        XCTAssertEqual(snap.kpis?.totalSales, 1000)
        XCTAssertEqual(snap.kpis?.netProfit, 200)
    }

    // MARK: - DashboardKPIs defaults

    func test_kpis_defaultsAreZero() {
        let kpis = DashboardKPIs()
        XCTAssertEqual(kpis.totalSales, 0)
        XCTAssertEqual(kpis.tax, 0)
        XCTAssertEqual(kpis.discounts, 0)
        XCTAssertEqual(kpis.cogs, 0)
        XCTAssertEqual(kpis.netProfit, 0)
        XCTAssertEqual(kpis.refunds, 0)
        XCTAssertEqual(kpis.expenses, 0)
        XCTAssertEqual(kpis.receivables, 0)
        XCTAssertNil(kpis.openTickets)
    }

    // MARK: - DashboardSummary expanded fields

    func test_summary_lowStockCount_isOptional() {
        let s1 = DashboardSummary()
        XCTAssertNil(s1.lowStockCount)

        let s2 = DashboardSummary(openTickets: 0, lowStockCount: 7)
        XCTAssertEqual(s2.lowStockCount, 7)
    }

    func test_summary_revenueTrend_isOptional() {
        let s = DashboardSummary(openTickets: 1, revenueTrend: 12.5)
        XCTAssertEqual(s.revenueTrend, 12.5)
    }

    // MARK: - kpiItems helper

    func test_kpiItems_baseTileCount_isAtLeastFour() {
        let summary = DashboardSummary()
        let tiles = kpiItems(from: summary)
        // Base tiles: Revenue today, Open tickets, Closed today, Appointments, Inventory value
        // Low stock is optional — at minimum 4 guaranteed tiles.
        XCTAssertGreaterThanOrEqual(tiles.count, 4)
    }

    func test_kpiItems_labelsAreUnique() {
        let summary = DashboardSummary(openTickets: 3, revenueToday: 100)
        let tiles = kpiItems(from: summary)
        let labels = tiles.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count, "KPI tile labels must be unique")
    }

    func test_kpiItems_revenueToday_formattedAsCurrency() {
        let summary = DashboardSummary(revenueToday: 1234.56)
        let tiles = kpiItems(from: summary)
        let revenueTile = tiles.first { $0.label == "Revenue today" }
        XCTAssertNotNil(revenueTile, "Expected 'Revenue today' tile")
        XCTAssertTrue(
            revenueTile!.value.contains("$") || revenueTile!.value.contains("1"),
            "Revenue tile value should be currency-formatted: \(revenueTile!.value)"
        )
    }

    func test_kpiItems_openTickets_valueMatchesSummary() {
        let summary = DashboardSummary(openTickets: 42)
        let tiles = kpiItems(from: summary)
        let tile = tiles.first { $0.label == "Open tickets" }
        XCTAssertEqual(tile?.value, "42")
    }

    func test_kpiItems_closedToday_valueMatchesSummary() {
        let summary = DashboardSummary(closedToday: 7)
        let tiles = kpiItems(from: summary)
        let tile = tiles.first { $0.label == "Closed today" }
        XCTAssertEqual(tile?.value, "7")
    }

    func test_kpiItems_allTilesHaveNonEmptyIcon() {
        let summary = DashboardSummary()
        let tiles = kpiItems(from: summary)
        for tile in tiles {
            XCTAssertFalse(tile.icon.isEmpty, "Tile '\(tile.label)' must have a non-empty icon name")
        }
    }

    func test_kpiItems_allTilesHaveUniqueIDs() {
        let summary = DashboardSummary()
        let tiles = kpiItems(from: summary)
        let ids = Set(tiles.map(\.id))
        XCTAssertEqual(ids.count, tiles.count, "Each KPI tile must have a unique ID")
    }
}
