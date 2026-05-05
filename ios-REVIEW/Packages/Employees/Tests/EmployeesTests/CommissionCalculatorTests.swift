import XCTest
@testable import Employees
import Networking

// MARK: - CommissionCalculatorTests
// TDD: written before CommissionCalculator was implemented.

final class CommissionCalculatorTests: XCTestCase {

    // MARK: - Helpers

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func makePeriod(days: Double = 30) -> DateInterval {
        DateInterval(start: base, duration: days * 86400)
    }

    private func makeSale(
        id: String = "S1",
        amount: Double,
        serviceCategory: String? = nil,
        productCategory: String? = nil,
        daysFromBase: Double = 1
    ) -> Sale {
        Sale(
            id: id,
            amount: amount,
            serviceCategory: serviceCategory,
            productCategory: productCategory,
            date: base.addingTimeInterval(daysFromBase * 86400)
        )
    }

    private func makePercentageRule(id: Int64 = 1, pct: Double, cap: Double? = nil, minTicket: Double? = nil) -> CommissionRule {
        CommissionRule(
            id: id,
            ruleType: .percentage,
            value: pct,
            capAmount: cap,
            condition: minTicket.map { CommissionCondition(minTicketValue: $0) }
        )
    }

    private func makeFlatRule(id: Int64 = 2, flat: Double, cap: Double? = nil) -> CommissionRule {
        CommissionRule(id: id, ruleType: .flat, value: flat, capAmount: cap)
    }

    // MARK: - Basic percentage

    func test_percentageRule_basicCalculation() {
        let rules = [makePercentageRule(pct: 10)]
        let sales = [makeSale(amount: 100)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1",
            period: makePeriod(),
            rules: rules,
            salesData: sales
        )
        XCTAssertEqual(report.total, 10.0, accuracy: 0.01)
    }

    func test_percentageRule_twoSales_summed() {
        let rules = [makePercentageRule(pct: 10)]
        let sales = [makeSale(id: "S1", amount: 100), makeSale(id: "S2", amount: 200)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 30.0, accuracy: 0.01)
    }

    // MARK: - Flat rate

    func test_flatRule_perSale() {
        let rules = [makeFlatRule(flat: 25)]
        let sales = [makeSale(id: "S1", amount: 500), makeSale(id: "S2", amount: 50)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 50.0, accuracy: 0.01)
    }

    // MARK: - Cap

    func test_percentageRule_cappedAtMax() {
        let rules = [makePercentageRule(pct: 10, cap: 5)]
        let sales = [makeSale(amount: 200)]  // 10% = 20, cap = 5
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 5.0, accuracy: 0.01)
    }

    func test_flatRule_cappedAtMax() {
        let rules = [makeFlatRule(flat: 100, cap: 40)]
        let sales = [makeSale(amount: 500)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 40.0, accuracy: 0.01)
    }

    // MARK: - Minimum threshold

    func test_minTicketValue_belowThreshold_noCommission() {
        let rules = [makePercentageRule(pct: 10, minTicket: 100)]
        let sales = [makeSale(amount: 50)]  // below $100 threshold
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
        XCTAssertTrue(report.lineItems.isEmpty)
    }

    func test_minTicketValue_aboveThreshold_earnsCommission() {
        let rules = [makePercentageRule(pct: 10, minTicket: 100)]
        let sales = [makeSale(amount: 150)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 15.0, accuracy: 0.01)
    }

    // MARK: - Tenure condition

    func test_tenureCondition_belowMinTenure_noCommission() {
        let rule = CommissionRule(
            id: 1,
            ruleType: .percentage,
            value: 5,
            condition: CommissionCondition(tenureMonths: 12)
        )
        let sales = [makeSale(amount: 100)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1",
            period: makePeriod(),
            rules: [rule],
            salesData: sales,
            employeeTenureMonths: 6  // less than 12
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
    }

    func test_tenureCondition_meetsMinTenure_earnsCommission() {
        let rule = CommissionRule(
            id: 1,
            ruleType: .percentage,
            value: 5,
            condition: CommissionCondition(tenureMonths: 12)
        )
        let sales = [makeSale(amount: 200)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1",
            period: makePeriod(),
            rules: [rule],
            salesData: sales,
            employeeTenureMonths: 24
        )
        XCTAssertEqual(report.total, 10.0, accuracy: 0.01)
    }

    // MARK: - Category scoping

    func test_serviceCategory_match() {
        let rule = CommissionRule(id: 1, serviceCategory: "repair", ruleType: .percentage, value: 10)
        let sales = [
            makeSale(id: "S1", amount: 100, serviceCategory: "repair"),
            makeSale(id: "S2", amount: 200, serviceCategory: "parts")
        ]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: [rule], salesData: sales
        )
        XCTAssertEqual(report.total, 10.0, accuracy: 0.01)
        XCTAssertEqual(report.lineItems.count, 1)
    }

    func test_noMatchingCategory_noCommission() {
        let rule = CommissionRule(id: 1, serviceCategory: "repair", ruleType: .percentage, value: 10)
        let sales = [makeSale(amount: 100, serviceCategory: "accessories")]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: [rule], salesData: sales
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
    }

    // MARK: - Outside period

    func test_saleOutsidePeriod_excluded() {
        let rules = [makePercentageRule(pct: 10)]
        // Sale is 50 days after base — outside 30-day period
        let sales = [makeSale(amount: 500, daysFromBase: 50)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(days: 30), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
    }

    // MARK: - Empty

    func test_noSales_zeroTotal() {
        let rules = [makePercentageRule(pct: 10)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: []
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
    }

    func test_noRules_zeroTotal() {
        let sales = [makeSale(amount: 300)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: [], salesData: sales
        )
        XCTAssertEqual(report.total, 0.0, accuracy: 0.01)
    }

    // MARK: - Report metadata

    func test_report_employeeIdPreserved() {
        let report = CommissionCalculator.calculate(
            employeeId: "emp-42", period: makePeriod(), rules: [], salesData: []
        )
        XCTAssertEqual(report.employeeId, "emp-42")
    }

    func test_report_periodPreserved() {
        let period = makePeriod(days: 7)
        let report = CommissionCalculator.calculate(
            employeeId: "e", period: period, rules: [], salesData: []
        )
        XCTAssertEqual(report.period, period)
    }

    // MARK: - Line items

    func test_lineItems_correctCount() {
        let rules = [makePercentageRule(id: 1, pct: 5), makePercentageRule(id: 2, pct: 3)]
        let sales = [makeSale(amount: 100)]
        let report = CommissionCalculator.calculate(
            employeeId: "emp1", period: makePeriod(), rules: rules, salesData: sales
        )
        XCTAssertEqual(report.lineItems.count, 2)
    }
}
