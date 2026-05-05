import XCTest
@testable import Employees

// MARK: - ScorecardAggregatorTests
// TDD: written first per §46 testing requirements.

final class ScorecardAggregatorTests: XCTestCase {

    // MARK: - compositeScore

    func test_compositeScore_perfectEmployee() {
        let card = EmployeeScorecard(
            employeeId: "emp1",
            ticketCloseRate: 1.0,
            slaCompliance: 1.0,
            avgCustomerRating: 5.0,
            revenueAttributed: 10000,
            commissionEarned: 1000,
            hoursWorked: 40,
            breaksTaken: 2,
            voidsTriggered: 0,
            overridesTriggered: 0
        )
        let score = ScorecardAggregator.compositeScore(card)
        // close(30) + sla(25) + rating(25) + noPenalty(20) = 100
        XCTAssertEqual(score, 100, accuracy: 1.0)
    }

    func test_compositeScore_worstEmployee() {
        let card = EmployeeScorecard(
            employeeId: "emp2",
            ticketCloseRate: 0.0,
            slaCompliance: 0.0,
            avgCustomerRating: 1.0,
            revenueAttributed: 0,
            commissionEarned: 0,
            hoursWorked: 40,
            breaksTaken: 0,
            voidsTriggered: 100,
            overridesTriggered: 100
        )
        let score = ScorecardAggregator.compositeScore(card)
        // close(0)+sla(0)+rating(0)+penalty≈0 → total ≈0
        XCTAssertLessThanOrEqual(score, 5.0)
    }

    func test_compositeScore_midRange() {
        let card = EmployeeScorecard(
            employeeId: "emp3",
            ticketCloseRate: 0.75,
            slaCompliance: 0.75,
            avgCustomerRating: 3.5,
            hoursWorked: 40,
            voidsTriggered: 1,
            overridesTriggered: 1
        )
        let score = ScorecardAggregator.compositeScore(card)
        XCTAssertGreaterThan(score, 40)
        XCTAssertLessThan(score, 80)
    }

    func test_compositeScore_zeroHoursNoCrash() {
        let card = EmployeeScorecard(employeeId: "emp4", hoursWorked: 0)
        // Should not divide by zero
        let score = ScorecardAggregator.compositeScore(card)
        XCTAssertFalse(score.isNaN)
        XCTAssertFalse(score.isInfinite)
    }

    // MARK: - teamAverage

    func test_teamAverage_empty_returnsZero() {
        let avg = ScorecardAggregator.teamAverage([], \.ticketCloseRate)
        XCTAssertEqual(avg, 0)
    }

    func test_teamAverage_singleEmployee() {
        let card = EmployeeScorecard(employeeId: "e1", ticketCloseRate: 0.8)
        let avg = ScorecardAggregator.teamAverage([card], \.ticketCloseRate)
        XCTAssertEqual(avg, 0.8, accuracy: 0.001)
    }

    func test_teamAverage_multipleEmployees() {
        let cards = [
            EmployeeScorecard(employeeId: "e1", ticketCloseRate: 0.6),
            EmployeeScorecard(employeeId: "e2", ticketCloseRate: 0.8),
            EmployeeScorecard(employeeId: "e3", ticketCloseRate: 1.0)
        ]
        let avg = ScorecardAggregator.teamAverage(cards, \.ticketCloseRate)
        XCTAssertEqual(avg, 0.8, accuracy: 0.001)
    }

    func test_teamAverage_revenueKeyPath() {
        let cards = [
            EmployeeScorecard(employeeId: "e1", revenueAttributed: 1000),
            EmployeeScorecard(employeeId: "e2", revenueAttributed: 3000)
        ]
        let avg = ScorecardAggregator.teamAverage(cards, \.revenueAttributed)
        XCTAssertEqual(avg, 2000, accuracy: 0.01)
    }

    // MARK: - EmployeeScorecard model

    func test_scorecard_defaultWindowDays() {
        let card = EmployeeScorecard(employeeId: "e")
        XCTAssertEqual(card.windowDays, 30)
    }

    func test_scorecard_idMatchesEmployeeId() {
        let card = EmployeeScorecard(employeeId: "test-id")
        XCTAssertEqual(card.id, "test-id")
    }
}
