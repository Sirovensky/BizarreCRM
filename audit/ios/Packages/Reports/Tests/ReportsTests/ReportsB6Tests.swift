import XCTest
@testable import Reports

// MARK: - ReportsB6Tests
//
// Batch-6 §15 additions:
//   §15.7 — WarrantyClaimsPoint, DeviceModelRepaired, PartUsageRow,
//            TechHoursRow, StalledTicketsSummary, CustomerAcquisitionChurn
//   §15.8 — CustomReportQuery, CustomReportStore, ReportEntity/Measure/GroupBy
//   §15.9 — RevenueByCategoryRow, RepeatCustomerStats, AvgTicketValueTrendPoint,
//            ConversionFunnelStats, LaborUtilizationRow
//   §15.9 — DrillBreadcrumb, DrillThroughState, SavedDrillTile, ChartImageExporter

// MARK: - §15.7 Model Tests

final class WarrantyClaimsTests: XCTestCase {

    // 1. WarrantyClaimsPoint unresolvedCount computed correctly
    func test_warrantyClaims_unresolvedCount() {
        let pt = WarrantyClaimsPoint(period: "Jan", claimsCount: 10, resolvedCount: 7, avgResolutionDays: 3.0)
        XCTAssertEqual(pt.unresolvedCount, 3)
    }

    // 2. WarrantyClaimsPoint decodes JSON
    func test_warrantyClaims_decodes() throws {
        let json = """
        {"period":"2024-01","claims_count":5,"resolved_count":3,"avg_resolution_days":2.5}
        """.data(using: .utf8)!
        let pt = try JSONDecoder().decode(WarrantyClaimsPoint.self, from: json)
        XCTAssertEqual(pt.period, "2024-01")
        XCTAssertEqual(pt.claimsCount, 5)
        XCTAssertEqual(pt.avgResolutionDays, 2.5, accuracy: 0.01)
    }

    // 3. DeviceModelRepaired decodes JSON
    func test_deviceModelRepaired_decodes() throws {
        let json = """
        {"model":"iPhone 15 Pro","repair_count":42,"revenue":8400.0}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(DeviceModelRepaired.self, from: json)
        XCTAssertEqual(row.model, "iPhone 15 Pro")
        XCTAssertEqual(row.repairCount, 42)
        XCTAssertEqual(row.revenueDollars, 8400.0, accuracy: 0.01)
    }

    // 4. PartUsageRow decodes JSON + costDollars
    func test_partUsageRow_decodes() throws {
        let json = """
        {"part_name":"Screen Digitizer","sku":"DIG-01","units_used":15,"total_cost":450.0}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(PartUsageRow.self, from: json)
        XCTAssertEqual(row.partName, "Screen Digitizer")
        XCTAssertEqual(row.unitsUsed, 15)
        XCTAssertEqual(row.totalCostDollars, 450.0, accuracy: 0.01)
    }

    // 5. TechHoursRow utilizationPct computed correctly
    func test_techHoursRow_utilizationPct() {
        let row = TechHoursRow(id: 1, techName: "Alice", billableHours: 32.0, nonBillableHours: 8.0)
        XCTAssertEqual(row.totalHours, 40.0, accuracy: 0.01)
        XCTAssertEqual(row.utilizationPct, 80.0, accuracy: 0.01)
    }

    // 6. TechHoursRow utilizationPct zero when no hours
    func test_techHoursRow_utilizationPct_zeroHours() {
        let row = TechHoursRow(id: 2, techName: "Bob", billableHours: 0, nonBillableHours: 0)
        XCTAssertEqual(row.utilizationPct, 0.0)
    }

    // 7. StalledTicketsSummary decodes JSON
    func test_stalledTickets_decodes() throws {
        let json = """
        {"stalled_count":5,"overdue_count":2,"avg_days_stalled":3.5,"top_stalled_tech":"Charlie"}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(StalledTicketsSummary.self, from: json)
        XCTAssertEqual(s.stalledCount, 5)
        XCTAssertEqual(s.avgDaysStalled, 3.5, accuracy: 0.01)
        XCTAssertEqual(s.topStalledTech, "Charlie")
    }

    // 8. CustomerAcquisitionChurn netGrowth positive
    func test_customerAcquisitionChurn_netGrowth_positive() {
        let d = CustomerAcquisitionChurn(newCustomers: 50, churnedCustomers: 20, returningCustomers: 15)
        XCTAssertEqual(d.netGrowth, 30)
    }

    // 9. CustomerAcquisitionChurn churnRatePct calculation
    func test_customerAcquisitionChurn_churnRatePct() {
        let d = CustomerAcquisitionChurn(newCustomers: 80, churnedCustomers: 20, returningCustomers: 10)
        // churnRate = 20/(80+20)*100 = 20%
        XCTAssertEqual(d.churnRatePct, 20.0, accuracy: 0.01)
    }

    // 10. CustomerAcquisitionChurn churnRatePct zero when no customers
    func test_customerAcquisitionChurn_churnRatePct_zero() {
        let d = CustomerAcquisitionChurn(newCustomers: 0, churnedCustomers: 0, returningCustomers: 0)
        XCTAssertEqual(d.churnRatePct, 0.0)
    }
}

// MARK: - §15.8 Custom Report Query Tests

final class CustomReportQueryTests: XCTestCase {

    // 11. CustomReportQuery has stable id
    func test_customReportQuery_stableId() {
        let q = CustomReportQuery(id: "test-id-123")
        XCTAssertEqual(q.id, "test-id-123")
    }

    // 12. CustomReportStore save + allQueries
    func test_customReportStore_saveAndRetrieve() {
        let store = CustomReportStore()
        let q = CustomReportQuery(id: "q1", name: "My Revenue Report", entity: .sales, measure: .revenue)
        store.save(q)
        let all = store.allQueries()
        XCTAssertTrue(all.contains(where: { $0.id == "q1" }))
    }

    // 13. CustomReportStore toggleFavorite
    func test_customReportStore_toggleFavorite() {
        let store = CustomReportStore()
        var q = CustomReportQuery(id: "q2", name: "Tickets", isFavorite: false)
        store.save(q)
        store.toggleFavorite(id: "q2")
        let favorites = store.favorites()
        XCTAssertTrue(favorites.contains(where: { $0.id == "q2" }))
    }

    // 14. CustomReportStore delete
    func test_customReportStore_delete() {
        let store = CustomReportStore()
        let q = CustomReportQuery(id: "q3-to-delete")
        store.save(q)
        store.delete(id: "q3-to-delete")
        XCTAssertFalse(store.allQueries().contains(where: { $0.id == "q3-to-delete" }))
    }

    // 15. ReportEntity availableMeasures includes revenue for sales
    func test_reportEntity_availableMeasures_sales() {
        XCTAssertTrue(ReportEntity.sales.availableMeasures.contains(.revenue))
    }

    // 16. ReportEntity availableMeasures changes on entity switch
    func test_reportEntity_availableMeasures_inventory() {
        XCTAssertFalse(ReportEntity.inventory.availableMeasures.contains(.revenue))
        XCTAssertTrue(ReportEntity.inventory.availableMeasures.contains(.stockValue))
    }
}

// MARK: - §15.9 BI Built-in Model Tests

final class BuiltInBITests: XCTestCase {

    // 17. RevenueByCategoryRow grossMarginPct
    func test_revenueByCategoryRow_grossMarginPct() {
        let row = RevenueByCategoryRow(category: "Screen Repair", revenueDollars: 1000, cogsDollars: 300)
        XCTAssertEqual(row.grossMarginPct, 70.0, accuracy: 0.01)
    }

    // 18. RevenueByCategoryRow grossMarginPct zero revenue
    func test_revenueByCategoryRow_grossMarginPct_zeroRevenue() {
        let row = RevenueByCategoryRow(category: "Empty", revenueDollars: 0, cogsDollars: 0)
        XCTAssertEqual(row.grossMarginPct, 0)
    }

    // 19. RepeatCustomerStats decodes JSON
    func test_repeatCustomerStats_decodes() throws {
        let json = """
        {"repeat_rate_pct":45.5,"avg_days_to_repeat":32.0,"one_time_count":55,"repeat_count":45}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(RepeatCustomerStats.self, from: json)
        XCTAssertEqual(s.repeatRatePct, 45.5, accuracy: 0.01)
        XCTAssertEqual(s.oneTimeCount, 55)
    }

    // 20. AvgTicketValueTrendPoint decodes JSON
    func test_avgTicketValueTrendPoint_decodes() throws {
        let json = """
        {"period":"2024-01","avg_value":125.50}
        """.data(using: .utf8)!
        let pt = try JSONDecoder().decode(AvgTicketValueTrendPoint.self, from: json)
        XCTAssertEqual(pt.avgValueDollars, 125.50, accuracy: 0.01)
    }

    // 21. ConversionFunnelStats overallConversionPct
    func test_conversionFunnel_overallConversionPct() {
        let s = ConversionFunnelStats(leadsCount: 100, estimatesCount: 80,
                                      ticketsCount: 60, invoicesCount: 50, paidCount: 40)
        XCTAssertEqual(s.overallConversionPct, 40.0, accuracy: 0.01)
    }

    // 22. ConversionFunnelStats leadsToEstimatesPct
    func test_conversionFunnel_leadsToEstimatesPct() {
        let s = ConversionFunnelStats(leadsCount: 100, estimatesCount: 75,
                                      ticketsCount: 50, invoicesCount: 40, paidCount: 30)
        XCTAssertEqual(s.leadsToEstimatesPct, 75.0, accuracy: 0.01)
    }

    // 23. ConversionFunnelStats zero leads → zero overall
    func test_conversionFunnel_zeroLeads() {
        let s = ConversionFunnelStats(leadsCount: 0, estimatesCount: 0,
                                      ticketsCount: 0, invoicesCount: 0, paidCount: 0)
        XCTAssertEqual(s.overallConversionPct, 0.0)
    }

    // 24. LaborUtilizationRow utilizationPct
    func test_laborUtilizationRow_utilizationPct() {
        let row = LaborUtilizationRow(id: 1, techName: "Dana", bookedHours: 40.0, productiveHours: 36.0)
        XCTAssertEqual(row.utilizationPct, 90.0, accuracy: 0.01)
    }

    // 25. LaborUtilizationRow zero booked → zero pct
    func test_laborUtilizationRow_zeroBooked() {
        let row = LaborUtilizationRow(id: 2, techName: "Eve", bookedHours: 0, productiveHours: 0)
        XCTAssertEqual(row.utilizationPct, 0.0)
    }
}

// MARK: - §15.9 Breadcrumb Drill Tests

final class BreadcrumbDrillTests: XCTestCase {

    // 26. DrillBreadcrumb has stable id
    func test_drillBreadcrumb_stableId() {
        let crumb = DrillBreadcrumb(id: "bc-1", label: "October", metric: "revenue", filter: "2024-10")
        XCTAssertEqual(crumb.id, "bc-1")
        XCTAssertEqual(crumb.label, "October")
    }

    // 27. DrillThroughState drillInto appends breadcrumb
    @MainActor
    func test_drillThroughState_drillInto_appendsCrumb() async {
        let stub = StubReportsRepository()
        let state = DrillThroughState(repository: stub)
        let crumb = DrillBreadcrumb(label: "October", metric: "revenue", filter: "2024-10-01")
        await state.drillInto(crumb: crumb)
        XCTAssertEqual(state.breadcrumbs.count, 1)
        XCTAssertEqual(state.breadcrumbs[0].label, "October")
    }

    // 28. DrillThroughState reset clears breadcrumbs
    @MainActor
    func test_drillThroughState_reset_clearsBreadcrumbs() async {
        let stub = StubReportsRepository()
        let state = DrillThroughState(repository: stub)
        let crumb = DrillBreadcrumb(label: "Oct", metric: "revenue", filter: "2024-10-01")
        await state.drillInto(crumb: crumb)
        state.reset()
        XCTAssertTrue(state.breadcrumbs.isEmpty)
        XCTAssertTrue(state.records.isEmpty)
    }

    // 29. DrillThroughState popTo truncates trail
    @MainActor
    func test_drillThroughState_popTo_truncatesTrail() async {
        let stub = StubReportsRepository()
        let state = DrillThroughState(repository: stub)
        let c1 = DrillBreadcrumb(label: "October", metric: "revenue", filter: "2024-10-01")
        let c2 = DrillBreadcrumb(label: "Services", metric: "revenue", filter: "2024-10-01")
        await state.drillInto(crumb: c1)
        await state.drillInto(crumb: c2)
        XCTAssertEqual(state.breadcrumbs.count, 2)
        await state.popTo(index: 0)
        XCTAssertEqual(state.breadcrumbs.count, 1)
        XCTAssertEqual(state.breadcrumbs[0].label, "October")
    }

    // 30. SavedDrillTileStore save + allTiles
    func test_savedDrillTileStore_saveAndRetrieve() {
        let store = SavedDrillTileStore()
        let crumb = DrillBreadcrumb(id: "crumb-1", label: "October Revenue", metric: "revenue", filter: "2024-10-01")
        store.save(crumb: crumb)
        let tiles = store.allTiles()
        XCTAssertTrue(tiles.contains(where: { $0.title == "October Revenue" }))
    }
}

// MARK: - §15.9 Chart Image Exporter Tests

final class ChartImageExporterTests: XCTestCase {

    // 31. exportAsCSV creates valid URL and CSV content
    @MainActor
    func test_chartCSVExporter_createsFile() {
        let entries: [(label: String, value: Double)] = [
            ("Jan", 1000.0),
            ("Feb", 1500.0),
            ("Mar", 1200.0)
        ]
        guard let url = ChartImageExporter.exportAsCSV(entries: entries, title: "Revenue Trend") else {
            XCTFail("Expected URL from exportAsCSV")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try? String(contentsOf: url, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("Jan") ?? false)
        XCTAssertTrue(content?.contains("1000.0") ?? false)
    }

    // 32. exportAsCSV file contains correct header
    @MainActor
    func test_chartCSVExporter_hasHeader() {
        let entries: [(label: String, value: Double)] = [("A", 1.0)]
        let url = ChartImageExporter.exportAsCSV(entries: entries, title: "Test")
        let content = try? String(contentsOf: url!, encoding: .utf8)
        XCTAssertTrue(content?.hasPrefix("Label,Value") ?? false)
    }
}
