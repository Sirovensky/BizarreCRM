import XCTest
@testable import Reports

// §15.2 Cohort Revenue Retention + §15.5 Shrinkage Trend — agent-6 b8 tests

final class ReportsB8Tests: XCTestCase {

    // MARK: - §15.2 CohortRetentionData decoding

    func test_cohortRetentionData_decodesFromServerShape() throws {
        let json = """
        {
            "cohorts": [
                {
                    "cohort_month": "2024-01",
                    "rows": [
                        { "month_offset": 0, "retention_pct": 100.0, "revenue": 5000.0 },
                        { "month_offset": 1, "retention_pct": 62.5, "revenue": 3200.0 },
                        { "month_offset": 2, "retention_pct": 45.0, "revenue": 2100.0 }
                    ]
                },
                {
                    "cohort_month": "2024-02",
                    "rows": [
                        { "month_offset": 0, "retention_pct": 100.0, "revenue": 4500.0 },
                        { "month_offset": 1, "retention_pct": 58.0, "revenue": 2900.0 }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!
        let data = try JSONDecoder().decode(CohortRetentionData.self, from: json)
        XCTAssertEqual(data.cohorts.count, 2)
        XCTAssertEqual(data.cohorts[0].cohortMonth, "2024-01")
        XCTAssertEqual(data.cohorts[0].cells.count, 3)
        XCTAssertEqual(data.cohorts[0].cells[1].monthOffset, 1)
        XCTAssertEqual(data.cohorts[0].cells[1].retentionPct, 62.5, accuracy: 0.01)
        XCTAssertEqual(data.cohorts[0].cells[1].revenueDollars, 3200.0, accuracy: 0.01)
    }

    func test_cohortRow_idMatchesCohortMonth() throws {
        let row = CohortRow(cohortMonth: "2024-03", cells: [])
        XCTAssertEqual(row.id, "2024-03")
    }

    func test_cohortCell_synthesisesId() throws {
        let cell = CohortCell(monthOffset: 3, retentionPct: 40.0, revenueDollars: 1500.0)
        XCTAssertEqual(cell.id, "3")
    }

    func test_cohortRetentionData_emptyCohortsDecodesGracefully() throws {
        let json = """{ "cohorts": [] }""".data(using: .utf8)!
        let data = try JSONDecoder().decode(CohortRetentionData.self, from: json)
        XCTAssertTrue(data.cohorts.isEmpty)
    }

    func test_cohortRetentionData_missingCohortsKeyGraceful() throws {
        let json = """{}""".data(using: .utf8)!
        let data = try JSONDecoder().decode(CohortRetentionData.self, from: json)
        XCTAssertTrue(data.cohorts.isEmpty)
    }

    // MARK: - §15.2 ViewModel loads cohort retention

    @MainActor
    func test_viewModel_loadsCohortRetention() async throws {
        let stub = StubReportsRepository()
        let cells = [
            CohortCell(monthOffset: 0, retentionPct: 100, revenueDollars: 3000),
            CohortCell(monthOffset: 1, retentionPct: 55, revenueDollars: 1500)
        ]
        let expected = CohortRetentionData(cohorts: [
            CohortRow(cohortMonth: "2024-01", cells: cells)
        ])
        await stub.setCohortRetentionResult(.success(expected))

        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()

        XCTAssertNotNil(vm.cohortRetention)
        XCTAssertEqual(vm.cohortRetention?.cohorts.count, 1)
        XCTAssertEqual(vm.cohortRetention?.cohorts.first?.cohortMonth, "2024-01")
    }

    @MainActor
    func test_viewModel_cohortRetentionRemainsNilOnError() async throws {
        let stub = StubReportsRepository()
        await stub.setCohortRetentionResult(.failure(URLError(.notConnectedToInternet)))

        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()

        XCTAssertNil(vm.cohortRetention)
    }

    // MARK: - §15.5 ShrinkagePoint decoding

    func test_shrinkagePoint_decodesFromServerShape() throws {
        let json = """
        {
            "period": "2024-01-15",
            "shrinkage_units": 12,
            "shrinkage_cost": 450.75,
            "reason": "theft"
        }
        """.data(using: .utf8)!
        let point = try JSONDecoder().decode(ShrinkagePoint.self, from: json)
        XCTAssertEqual(point.period, "2024-01-15")
        XCTAssertEqual(point.shrinkageUnits, 12)
        XCTAssertEqual(point.shrinkageCostDollars, 450.75, accuracy: 0.01)
        XCTAssertEqual(point.reason, "theft")
        XCTAssertEqual(point.id, "2024-01-15-theft")
    }

    func test_shrinkagePoint_missingFieldsGraceful() throws {
        let json = """{}""".data(using: .utf8)!
        let point = try JSONDecoder().decode(ShrinkagePoint.self, from: json)
        XCTAssertEqual(point.shrinkageUnits, 0)
        XCTAssertEqual(point.shrinkageCostDollars, 0.0, accuracy: 0.01)
        XCTAssertEqual(point.reason, "other")
    }

    func test_shrinkagePoint_reasonDisplayName_theft() {
        let p = ShrinkagePoint(period: "2024-01", shrinkageUnits: 1, shrinkageCostDollars: 10, reason: "theft")
        XCTAssertEqual(p.reasonDisplayName, "Theft")
    }

    func test_shrinkagePoint_reasonDisplayName_damage() {
        let p = ShrinkagePoint(period: "2024-01", shrinkageUnits: 1, shrinkageCostDollars: 10, reason: "damage")
        XCTAssertEqual(p.reasonDisplayName, "Damage")
    }

    func test_shrinkagePoint_reasonDisplayName_unknown_capitalized() {
        let p = ShrinkagePoint(period: "2024-01", shrinkageUnits: 1, shrinkageCostDollars: 10, reason: "mystery")
        XCTAssertEqual(p.reasonDisplayName, "Mystery")
    }

    func test_shrinkageSummary_decodesFromServerShape() throws {
        let json = """
        {
            "total_units": 45,
            "total_cost": 2100.50,
            "shrinkage_pct": 1.75
        }
        """.data(using: .utf8)!
        let summary = try JSONDecoder().decode(ShrinkageSummary.self, from: json)
        XCTAssertEqual(summary.totalUnits, 45)
        XCTAssertEqual(summary.totalCostDollars, 2100.50, accuracy: 0.01)
        XCTAssertEqual(summary.shrinkagePct, 1.75, accuracy: 0.001)
    }

    func test_shrinkageReport_decodesRowsAndSummary() throws {
        let json = """
        {
            "rows": [
                { "period": "2024-01", "shrinkage_units": 5, "shrinkage_cost": 200.0, "reason": "damage" },
                { "period": "2024-02", "shrinkage_units": 8, "shrinkage_cost": 320.0, "reason": "theft" }
            ],
            "summary": { "total_units": 13, "total_cost": 520.0, "shrinkage_pct": 1.2 }
        }
        """.data(using: .utf8)!
        let report = try JSONDecoder().decode(ShrinkageReport.self, from: json)
        XCTAssertEqual(report.rows.count, 2)
        XCTAssertNotNil(report.summary)
        XCTAssertEqual(report.summary?.totalUnits, 13)
        XCTAssertEqual(report.summary?.shrinkagePct, 1.2, accuracy: 0.001)
    }

    func test_shrinkageReport_missingRowsGraceful() throws {
        let json = """{}""".data(using: .utf8)!
        let report = try JSONDecoder().decode(ShrinkageReport.self, from: json)
        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertNil(report.summary)
    }

    // MARK: - §15.5 ViewModel loads shrinkage

    @MainActor
    func test_viewModel_loadsShrinkageReport() async throws {
        let stub = StubReportsRepository()
        let report = ShrinkageReport(
            rows: [
                ShrinkagePoint(period: "2024-01", shrinkageUnits: 5,
                               shrinkageCostDollars: 200, reason: "theft")
            ],
            summary: ShrinkageSummary(totalUnits: 5, totalCostDollars: 200, shrinkagePct: 1.1)
        )
        await stub.setShrinkageResult(.success(report))

        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()

        XCTAssertNotNil(vm.shrinkageReport)
        XCTAssertEqual(vm.shrinkageReport?.rows.count, 1)
        XCTAssertEqual(vm.shrinkageReport?.summary?.totalUnits, 5)
    }

    @MainActor
    func test_viewModel_shrinkageRemainsNilOnError() async throws {
        let stub = StubReportsRepository()
        await stub.setShrinkageResult(.failure(URLError(.notConnectedToInternet)))

        let vm = ReportsViewModel(repository: stub)
        await vm.loadAll()

        XCTAssertNil(vm.shrinkageReport)
    }
}

// MARK: - StubReportsRepository actor mutators for b8

extension StubReportsRepository {
    func setCohortRetentionResult(_ r: Result<CohortRetentionData, Error>) {
        cohortRetentionResult = r
    }
    func setShrinkageResult(_ r: Result<ShrinkageReport, Error>) {
        shrinkageResult = r
    }
}
