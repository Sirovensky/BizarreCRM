import XCTest
@testable import Reports

// MARK: - Batch-4 tests covering §15.1, §15.2, §15.4, §15.6

final class ReportSubTabTests: XCTestCase {

    func test_allCasesCount() {
        XCTAssertEqual(ReportSubTab.allCases.count, 6)
    }

    func test_caseRawValues() {
        XCTAssertEqual(ReportSubTab.sales.rawValue,     "Sales")
        XCTAssertEqual(ReportSubTab.tickets.rawValue,   "Tickets")
        XCTAssertEqual(ReportSubTab.employees.rawValue, "Employees")
        XCTAssertEqual(ReportSubTab.inventory.rawValue, "Inventory")
        XCTAssertEqual(ReportSubTab.tax.rawValue,       "Tax")
        XCTAssertEqual(ReportSubTab.insights.rawValue,  "Insights")
    }

    func test_idMatchesRawValue() {
        for tab in ReportSubTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }

    func test_allHaveSystemImages() {
        for tab in ReportSubTab.allCases {
            XCTAssertFalse(tab.systemImage.isEmpty, "\(tab) has empty systemImage")
        }
    }
}

// MARK: - SalesTotals KPI derivation

final class SalesKPITests: XCTestCase {

    func test_avgInvoice_whenZeroInvoices_isZero() {
        let totals = SalesTotals(totalRevenue: 0, totalInvoices: 0, uniqueCustomers: 0)
        let avg = totals.totalInvoices > 0
            ? totals.totalRevenue / Double(totals.totalInvoices)
            : 0.0
        XCTAssertEqual(avg, 0.0)
    }

    func test_avgInvoice_computed() {
        let totals = SalesTotals(totalRevenue: 3000, totalInvoices: 10, uniqueCustomers: 7)
        let avg = totals.totalRevenue / Double(totals.totalInvoices)
        XCTAssertEqual(avg, 300.0)
    }

    func test_revenueChangePct_positive() {
        let totals = SalesTotals(totalRevenue: 1100, revenueChangePct: 10.0, totalInvoices: 5, uniqueCustomers: 3)
        XCTAssertEqual(totals.revenueChangePct, 10.0)
    }

    func test_revenueChangePct_nil_whenNotProvided() {
        let totals = SalesTotals()
        XCTAssertNil(totals.revenueChangePct)
    }
}

// MARK: - PaymentMethodPoint decode

final class PaymentMethodPieTests: XCTestCase {

    func test_paymentMethodPoint_decode_fromJSON() throws {
        let json = #"""
        {"method":"cash","revenue":1200.50,"count":8}
        """#.data(using: .utf8)!
        let pt = try JSONDecoder().decode(PaymentMethodPoint.self, from: json)
        XCTAssertEqual(pt.method, "cash")
        XCTAssertEqual(pt.revenue, 1200.50, accuracy: 0.001)
        XCTAssertEqual(pt.count, 8)
        XCTAssertEqual(pt.id, "cash")
    }

    func test_paymentMethodPoint_fallbackMethod() throws {
        let json = #"""
        {}
        """#.data(using: .utf8)!
        let pt = try JSONDecoder().decode(PaymentMethodPoint.self, from: json)
        XCTAssertEqual(pt.method, "Other")
    }
}

// MARK: - TechnicianPerfRow decode + closeRate

final class TechnicianPerfTests: XCTestCase {

    private func makeRow(assigned: Int, closed: Int) -> TechnicianPerfRow {
        TechnicianPerfRow(
            id: 1, name: "Alice",
            ticketsAssigned: assigned, ticketsClosed: closed,
            commissionDollars: 200, hoursWorked: 8.0, revenueGenerated: 5000
        )
    }

    func test_closeRate_perfect() {
        XCTAssertEqual(makeRow(assigned: 10, closed: 10).closeRate, 100.0)
    }

    func test_closeRate_half() {
        XCTAssertEqual(makeRow(assigned: 10, closed: 5).closeRate, 50.0)
    }

    func test_closeRate_zeroAssigned() {
        XCTAssertEqual(makeRow(assigned: 0, closed: 0).closeRate, 0.0)
    }

    func test_decode_fromJSON() throws {
        let json = #"""
        {
          "id": 42,
          "name": "Bob",
          "tickets_assigned": 20,
          "tickets_closed": 15,
          "commission_earned": 350.0,
          "hours_worked": 40.0,
          "revenue_generated": 8000.0
        }
        """#.data(using: .utf8)!
        let row = try JSONDecoder().decode(TechnicianPerfRow.self, from: json)
        XCTAssertEqual(row.id, 42)
        XCTAssertEqual(row.name, "Bob")
        XCTAssertEqual(row.ticketsAssigned, 20)
        XCTAssertEqual(row.ticketsClosed, 15)
        XCTAssertEqual(row.commissionDollars, 350.0, accuracy: 0.001)
        XCTAssertEqual(row.hoursWorked, 40.0, accuracy: 0.001)
        XCTAssertEqual(row.revenueGenerated, 8000.0, accuracy: 0.001)
        XCTAssertEqual(row.closeRate, 75.0, accuracy: 0.001)
    }
}

// MARK: - TaxEntry + TaxReportResponse decode

final class TaxReportTests: XCTestCase {

    func test_taxEntry_decode() throws {
        let json = #"""
        {"tax_class":"CA Sales Tax","rate":8.25,"collected":420.75}
        """#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(TaxEntry.self, from: json)
        XCTAssertEqual(entry.taxClass, "CA Sales Tax")
        XCTAssertEqual(entry.rate, 8.25, accuracy: 0.001)
        XCTAssertEqual(entry.collected, 420.75, accuracy: 0.001)
    }

    func test_taxReportResponse_decode_emptyEntries() throws {
        let json = #"""
        {"by_class":[],"period_total":0}
        """#.data(using: .utf8)!
        let r = try JSONDecoder().decode(TaxReportResponse.self, from: json)
        XCTAssertTrue(r.entries.isEmpty)
        XCTAssertEqual(r.periodTotal, 0)
    }

    func test_taxReportResponse_decode_withEntries() throws {
        let json = #"""
        {
          "by_class":[
            {"tax_class":"State","rate":6.0,"collected":300.0},
            {"tax_class":"County","rate":2.0,"collected":100.0}
          ],
          "period_total":400.0
        }
        """#.data(using: .utf8)!
        let r = try JSONDecoder().decode(TaxReportResponse.self, from: json)
        XCTAssertEqual(r.entries.count, 2)
        XCTAssertEqual(r.periodTotal, 400.0, accuracy: 0.001)
    }

    func test_taxReportResponse_defaultInit() {
        let r = TaxReportResponse()
        XCTAssertTrue(r.entries.isEmpty)
        XCTAssertEqual(r.periodTotal, 0)
    }
}

// MARK: - ReportsViewModel subTab default

final class ReportsViewModelSubTabTests: XCTestCase {

    @MainActor
    func test_defaultSubTab_isSales() {
        let vm = ReportsViewModel(repository: StubReportsRepository())
        XCTAssertEqual(vm.selectedSubTab, .sales)
    }

    @MainActor
    func test_subTabChange() {
        let vm = ReportsViewModel(repository: StubReportsRepository())
        vm.selectedSubTab = .tax
        XCTAssertEqual(vm.selectedSubTab, .tax)
    }
}
