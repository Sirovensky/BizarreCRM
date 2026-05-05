import XCTest
@testable import Employees

// MARK: - PTOBalanceTrackerTests
// TDD: written first per §46 testing requirements.

final class PTOBalanceTrackerTests: XCTestCase {

    // Fixed reference: 2024-07-01 (halfway through year)
    private let midYear = Date(timeIntervalSince1970: 1_719_792_000) // 2024-07-01 00:00 UTC
    private let startYear = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00 UTC
    private let endYear   = Date(timeIntervalSince1970: 1_735_603_200) // 2025-01-01 00:00 UTC

    // MARK: - Zero accrual

    func test_zeroAccrual_returnsZero() {
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 0,
            usedDays: 0,
            asOf: midYear,
            hireDate: startYear
        )
        XCTAssertEqual(balance, 0, accuracy: 0.01)
    }

    // MARK: - Full year accrual

    func test_fullYearAccrual_noUsage() {
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 15,
            usedDays: 0,
            asOf: endYear,
            hireDate: startYear
        )
        // Should be close to 15 (full year)
        XCTAssertEqual(balance, 15, accuracy: 0.5)
    }

    // MARK: - Partial year accrual (~50%)

    func test_halfYearAccrual() {
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 10,
            usedDays: 0,
            asOf: midYear,
            hireDate: startYear
        )
        // ~50% of 10 = ~5
        XCTAssertGreaterThan(balance, 4.0)
        XCTAssertLessThan(balance, 6.0)
    }

    // MARK: - Usage deducted

    func test_usageDeducted() {
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 10,
            usedDays: 3,
            asOf: midYear,
            hireDate: startYear
        )
        let noUsage = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 10,
            usedDays: 0,
            asOf: midYear,
            hireDate: startYear
        )
        XCTAssertEqual(balance, noUsage - 3, accuracy: 0.01)
    }

    // MARK: - Balance never negative

    func test_balanceNeverNegative_whenOverUsed() {
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 5,
            usedDays: 100,   // way over accrual
            asOf: midYear,
            hireDate: startYear
        )
        XCTAssertEqual(balance, 0, accuracy: 0.01)
    }

    // MARK: - Hire date after asOf clamps to zero

    func test_hireDateAfterAsOf_returnsZero() {
        let futureHire = Date(timeIntervalSince1970: midYear.timeIntervalSince1970 + 86400 * 30)
        let balance = PTOBalanceTracker.computeBalance(
            employeeId: "emp1",
            accrualRate: 15,
            usedDays: 0,
            asOf: midYear,
            hireDate: futureHire
        )
        XCTAssertEqual(balance, 0, accuracy: 0.01)
    }

    // MARK: - PTORequest calendar days

    func test_ptoCalendarDays_sameDay() {
        let req = PTORequest(
            id: "r1", employeeId: "e1", type: .vacation,
            startDate: midYear, endDate: midYear
        )
        XCTAssertEqual(req.calendarDays, 1)
    }

    func test_ptoCalendarDays_multiDay() {
        let end = midYear.addingTimeInterval(86400 * 4)
        let req = PTORequest(
            id: "r2", employeeId: "e2", type: .sick,
            startDate: midYear, endDate: end
        )
        XCTAssertEqual(req.calendarDays, 5)
    }
}
