import XCTest
@testable import Invoices

// §7.9 InstallmentCalculator tests — ≥80% coverage required

final class InstallmentCalculatorTests: XCTestCase {

    // MARK: - distribute: basic split

    func test_distribute_evenSplit_allAmountsEqual() {
        let items = InstallmentCalculator.distribute(
            totalCents: 30000,
            count: 3,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.amountCents == 10000 })
    }

    func test_distribute_remainderGoesToLastInstallment() {
        // 10001 / 3 = 3333 remainder 2 → last gets 3335
        let items = InstallmentCalculator.distribute(
            totalCents: 10001,
            count: 3,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].amountCents, 3333)
        XCTAssertEqual(items[1].amountCents, 3333)
        XCTAssertEqual(items[2].amountCents, 3335)
        // Sum must match total
        XCTAssertEqual(items.reduce(0) { $0 + $1.amountCents }, 10001)
    }

    func test_distribute_sumAlwaysEqualTotal() {
        let totals = [1, 99, 100, 1001, 99999, 12345]
        let counts = [1, 2, 3, 7, 12]
        for total in totals {
            for count in counts {
                let items = InstallmentCalculator.distribute(
                    totalCents: total,
                    count: count,
                    startDate: makeDate(2024, 6, 1),
                    interval: .month
                )
                let sum = items.reduce(0) { $0 + $1.amountCents }
                XCTAssertEqual(sum, total, "Sum \(sum) != total \(total) for count \(count)")
            }
        }
    }

    func test_distribute_singleInstallment_fullAmount() {
        let items = InstallmentCalculator.distribute(
            totalCents: 5000,
            count: 1,
            startDate: makeDate(2024, 3, 15),
            interval: .month
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].amountCents, 5000)
    }

    func test_distribute_monthlyDates_incrementByMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = makeDate(2024, 1, 15)
        let items = InstallmentCalculator.distribute(
            totalCents: 30000,
            count: 3,
            startDate: start,
            interval: .month,
            calendar: cal
        )
        XCTAssertEqual(items.count, 3)
        let comps0 = cal.dateComponents([.month, .day, .year], from: items[0].dueDate)
        let comps1 = cal.dateComponents([.month, .day, .year], from: items[1].dueDate)
        let comps2 = cal.dateComponents([.month, .day, .year], from: items[2].dueDate)
        XCTAssertEqual(comps0.month, 1)
        XCTAssertEqual(comps1.month, 2)
        XCTAssertEqual(comps2.month, 3)
    }

    func test_distribute_weeklyDates_incrementByWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = makeDate(2024, 1, 1)
        let items = InstallmentCalculator.distribute(
            totalCents: 20000,
            count: 4,
            startDate: start,
            interval: .weekOfYear,
            calendar: cal
        )
        XCTAssertEqual(items.count, 4)
        // Each item 7 days apart
        for i in 1 ..< items.count {
            let diff = cal.dateComponents([.day], from: items[i-1].dueDate, to: items[i].dueDate).day ?? 0
            XCTAssertEqual(diff, 7, "Expected 7 days between installments \(i-1) and \(i)")
        }
    }

    func test_distribute_zeroTotal_returnsEmpty() {
        let items = InstallmentCalculator.distribute(
            totalCents: 0,
            count: 3,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertTrue(items.isEmpty)
    }

    func test_distribute_countZero_returnsEmpty() {
        let items = InstallmentCalculator.distribute(
            totalCents: 10000,
            count: 0,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertTrue(items.isEmpty)
    }

    func test_distribute_negativeCount_returnsEmpty() {
        let items = InstallmentCalculator.distribute(
            totalCents: 10000,
            count: -1,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertTrue(items.isEmpty)
    }

    func test_distribute_twelveSplit_allPositive() {
        let items = InstallmentCalculator.distribute(
            totalCents: 1200,
            count: 12,
            startDate: makeDate(2024, 1, 1),
            interval: .month
        )
        XCTAssertEqual(items.count, 12)
        XCTAssertTrue(items.allSatisfy { $0.amountCents > 0 })
    }

    // MARK: - isBalanced

    func test_isBalanced_matchingSum_returnsTrue() {
        let items = [
            ComputedInstallmentItem(dueDate: makeDate(2024, 1, 1), amountCents: 5000),
            ComputedInstallmentItem(dueDate: makeDate(2024, 2, 1), amountCents: 5000)
        ]
        XCTAssertTrue(InstallmentCalculator.isBalanced(items: items, expectedTotal: 10000))
    }

    func test_isBalanced_mismatch_returnsFalse() {
        let items = [
            ComputedInstallmentItem(dueDate: makeDate(2024, 1, 1), amountCents: 4999),
            ComputedInstallmentItem(dueDate: makeDate(2024, 2, 1), amountCents: 5000)
        ]
        XCTAssertFalse(InstallmentCalculator.isBalanced(items: items, expectedTotal: 10000))
    }

    // MARK: - isValid

    func test_isValid_nonEmptyPositiveAmountsNoDupeDates_returnsTrue() {
        let items = [
            ComputedInstallmentItem(dueDate: makeDate(2024, 1, 1), amountCents: 5000),
            ComputedInstallmentItem(dueDate: makeDate(2024, 2, 1), amountCents: 5000)
        ]
        XCTAssertTrue(InstallmentCalculator.isValid(items: items))
    }

    func test_isValid_emptyArray_returnsFalse() {
        XCTAssertFalse(InstallmentCalculator.isValid(items: []))
    }

    func test_isValid_zeroCentItem_returnsFalse() {
        let items = [
            ComputedInstallmentItem(dueDate: makeDate(2024, 1, 1), amountCents: 0),
            ComputedInstallmentItem(dueDate: makeDate(2024, 2, 1), amountCents: 5000)
        ]
        XCTAssertFalse(InstallmentCalculator.isValid(items: items))
    }

    func test_isValid_duplicateDates_returnsFalse() {
        let date = makeDate(2024, 1, 1)
        let items = [
            ComputedInstallmentItem(dueDate: date, amountCents: 5000),
            ComputedInstallmentItem(dueDate: date, amountCents: 5000)
        ]
        XCTAssertFalse(InstallmentCalculator.isValid(items: items))
    }

    // MARK: - distribute from calculator always passes isBalanced + isValid

    func test_distributeOutput_alwaysBalancedAndValid() {
        let start = makeDate(2024, 1, 1)
        for count in 1...12 {
            let total = count * 1000 + 7  // introduces non-divisible remainder
            let items = InstallmentCalculator.distribute(
                totalCents: total,
                count: count,
                startDate: start,
                interval: .month
            )
            XCTAssertTrue(
                InstallmentCalculator.isBalanced(items: items, expectedTotal: total),
                "Not balanced for count \(count)"
            )
            XCTAssertTrue(
                InstallmentCalculator.isValid(items: items),
                "Not valid for count \(count)"
            )
        }
    }

    // MARK: - Helpers

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
