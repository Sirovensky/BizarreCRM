import XCTest
@testable import Reports

final class PnLCalculatorTests: XCTestCase {

    // MARK: - compute

    func test_compute_allZero_returnsZeroSnapshot() {
        let snap = PnLCalculator.compute(revenues: [], cogs: [], expenses: [])
        XCTAssertEqual(snap.revenueCents, 0)
        XCTAssertEqual(snap.cogsCents, 0)
        XCTAssertEqual(snap.expensesCents, 0)
        XCTAssertEqual(snap.grossProfitCents, 0)
        XCTAssertEqual(snap.netCents, 0)
    }

    func test_compute_revenueOnly() {
        let revenues = [
            makeSale(id: "1", amountCents: 10000),
            makeSale(id: "2", amountCents: 5000)
        ]
        let snap = PnLCalculator.compute(revenues: revenues, cogs: [], expenses: [])
        XCTAssertEqual(snap.revenueCents, 15000)
        XCTAssertEqual(snap.grossProfitCents, 15000)
        XCTAssertEqual(snap.netCents, 15000)
    }

    func test_compute_withCOGS() {
        let revenues = [makeSale(id: "1", amountCents: 20000)]
        let cogs     = [makeCOGS(id: "1", amountCents: 8000)]
        let snap = PnLCalculator.compute(revenues: revenues, cogs: cogs, expenses: [])
        XCTAssertEqual(snap.grossProfitCents, 12000)
        XCTAssertEqual(snap.netCents, 12000)
    }

    func test_compute_fullPnL() {
        let revenues = [makeSale(id: "1", amountCents: 50000)]
        let cogs     = [makeCOGS(id: "1", amountCents: 20000)]
        let expenses = [makeExpense(id: "1", amountCents: 5000)]
        let snap = PnLCalculator.compute(revenues: revenues, cogs: cogs, expenses: expenses)
        XCTAssertEqual(snap.revenueCents, 50000)
        XCTAssertEqual(snap.cogsCents, 20000)
        XCTAssertEqual(snap.expensesCents, 5000)
        XCTAssertEqual(snap.grossProfitCents, 30000)
        XCTAssertEqual(snap.netCents, 25000)
    }

    func test_compute_netLoss() {
        let revenues = [makeSale(id: "1", amountCents: 1000)]
        let cogs     = [makeCOGS(id: "1", amountCents: 3000)]
        let snap = PnLCalculator.compute(revenues: revenues, cogs: cogs, expenses: [])
        XCTAssertEqual(snap.netCents, -2000)
    }

    // MARK: - grossMarginPct

    func test_grossMarginPct_typical() {
        let snap = PnLSnapshot(revenueCents: 10000, cogsCents: 4000, expensesCents: 0)
        XCTAssertEqual(snap.grossMarginPct, 0.6, accuracy: 0.001)
    }

    func test_grossMarginPct_zeroRevenue_returnsZero() {
        let snap = PnLSnapshot(revenueCents: 0, cogsCents: 0, expensesCents: 0)
        XCTAssertEqual(snap.grossMarginPct, 0.0)
    }

    func test_netMarginPct_typical() {
        let snap = PnLSnapshot(revenueCents: 10000, cogsCents: 3000, expensesCents: 2000)
        XCTAssertEqual(snap.netMarginPct, 0.5, accuracy: 0.001)
    }

    // MARK: - revenueByCustomer

    func test_revenueByCustomer_groupsCorrectly() {
        let sales = [
            makeSale(id: "1", amountCents: 5000, customerId: "A", customerName: "Alice"),
            makeSale(id: "2", amountCents: 3000, customerId: "A", customerName: "Alice"),
            makeSale(id: "3", amountCents: 9000, customerId: "B", customerName: "Bob")
        ]
        let grouped = PnLCalculator.revenueByCustomer(revenues: sales)
        XCTAssertEqual(grouped.count, 2)
        let alice = grouped.first { $0.customerId == "A" }
        XCTAssertEqual(alice?.totalCents, 8000)
        let bob = grouped.first { $0.customerId == "B" }
        XCTAssertEqual(bob?.totalCents, 9000)
    }

    func test_revenueByCustomer_sortedDescending() {
        let sales = [
            makeSale(id: "1", amountCents: 100, customerId: "low",  customerName: "Low"),
            makeSale(id: "2", amountCents: 900, customerId: "high", customerName: "High")
        ]
        let grouped = PnLCalculator.revenueByCustomer(revenues: sales)
        XCTAssertEqual(grouped.first?.customerId, "high")
    }

    // MARK: - topCustomers

    func test_topCustomers_limitsToN() {
        let sales = (1...15).map {
            makeSale(id: "\($0)", amountCents: $0 * 100, customerId: "C\($0)", customerName: "Customer \($0)")
        }
        let top = PnLCalculator.topCustomers(revenues: sales, limit: 10)
        XCTAssertEqual(top.count, 10)
    }

    // MARK: - expensesByCategory

    func test_expensesByCategory_groupsAndSorts() {
        let expenses = [
            makeExpense(id: "1", amountCents: 500,  category: "Supplies"),
            makeExpense(id: "2", amountCents: 1500, category: "Rent"),
            makeExpense(id: "3", amountCents: 300,  category: "Supplies")
        ]
        let grouped = PnLCalculator.expensesByCategory(expenses: expenses)
        XCTAssertEqual(grouped.first?.category, "Rent")
        let supplies = grouped.first { $0.category == "Supplies" }
        XCTAssertEqual(supplies?.amountCents, 800)
    }

    // MARK: - Helpers

    private func makeSale(
        id: String,
        amountCents: Int,
        customerId: String? = nil,
        customerName: String? = nil
    ) -> Sale {
        Sale(id: id, date: Date(), amountCents: amountCents,
             customerId: customerId, customerName: customerName)
    }

    private func makeCOGS(id: String, amountCents: Int) -> COGSEntry {
        COGSEntry(id: id, date: Date(), amountCents: amountCents, description: "COGS \(id)")
    }

    private func makeExpense(id: String, amountCents: Int, category: String = "Misc") -> FinancialExpense {
        FinancialExpense(id: id, date: Date(), amountCents: amountCents,
                         category: category, description: "Expense \(id)")
    }
}
