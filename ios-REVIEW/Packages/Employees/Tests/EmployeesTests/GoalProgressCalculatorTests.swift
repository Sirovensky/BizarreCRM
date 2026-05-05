import XCTest
@testable import Employees

// MARK: - GoalProgressCalculatorTests
// TDD: written first per §46 testing requirements.

final class GoalProgressCalculatorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        base.addingTimeInterval(Double(offset) * 86400)
    }

    // MARK: - progressFraction

    func test_progressFraction_zero() {
        let g = makeGoal(current: 0, target: 100)
        XCTAssertEqual(g.progressFraction, 0, accuracy: 0.001)
    }

    func test_progressFraction_half() {
        let g = makeGoal(current: 50, target: 100)
        XCTAssertEqual(g.progressFraction, 0.5, accuracy: 0.001)
    }

    func test_progressFraction_complete() {
        let g = makeGoal(current: 100, target: 100)
        XCTAssertEqual(g.progressFraction, 1.0, accuracy: 0.001)
    }

    func test_progressFraction_clampsAboveOne() {
        let g = makeGoal(current: 150, target: 100)
        XCTAssertEqual(g.progressFraction, 1.0, accuracy: 0.001)
    }

    func test_progressFraction_zeroTarget_returnsZero() {
        let g = makeGoal(current: 50, target: 0)
        XCTAssertEqual(g.progressFraction, 0, accuracy: 0.001)
    }

    // MARK: - streakDays

    func test_streak_empty_returnsZero() {
        let streak = GoalProgressCalculator.streakDays(from: [])
        XCTAssertEqual(streak, 0)
    }

    func test_streak_allTrue() {
        let history: [(Date, Bool)] = (0..<5).map { (day($0), true) }
        let streak = GoalProgressCalculator.streakDays(from: history)
        XCTAssertEqual(streak, 5)
    }

    func test_streak_breaksOnMiss() {
        let history: [(Date, Bool)] = [
            (day(0), true),
            (day(1), false),
            (day(2), true),
            (day(3), true),
        ]
        // Most recent two are true, but reversed scan stops at day(1) miss
        let streak = GoalProgressCalculator.streakDays(from: history)
        XCTAssertEqual(streak, 2)
    }

    func test_streak_singleMiss() {
        let history: [(Date, Bool)] = [(day(0), false)]
        let streak = GoalProgressCalculator.streakDays(from: history)
        XCTAssertEqual(streak, 0)
    }

    // MARK: - milestoneTier

    func test_milestoneTier_belowFifty() {
        XCTAssertNil(GoalProgressCalculator.milestoneTier(fraction: 0.49))
    }

    func test_milestoneTier_atFifty() {
        XCTAssertEqual(GoalProgressCalculator.milestoneTier(fraction: 0.50), 50)
    }

    func test_milestoneTier_atSeventyFive() {
        XCTAssertEqual(GoalProgressCalculator.milestoneTier(fraction: 0.75), 75)
    }

    func test_milestoneTier_atOneHundred() {
        XCTAssertEqual(GoalProgressCalculator.milestoneTier(fraction: 1.0), 100)
    }

    func test_milestoneTier_aboveHundred() {
        XCTAssertEqual(GoalProgressCalculator.milestoneTier(fraction: 1.2), 100)
    }

    // MARK: - newMilestonesCrossed

    func test_newMilestones_none() {
        let crossed = GoalProgressCalculator.newMilestonesCrossed(from: 0.8, to: 0.85)
        XCTAssertTrue(crossed.isEmpty)
    }

    func test_newMilestones_crossesFifty() {
        let crossed = GoalProgressCalculator.newMilestonesCrossed(from: 0.4, to: 0.55)
        XCTAssertEqual(crossed, [50])
    }

    func test_newMilestones_crossesFiftyAndSeventyFive() {
        let crossed = GoalProgressCalculator.newMilestonesCrossed(from: 0.4, to: 0.8)
        XCTAssertEqual(crossed, [50, 75])
    }

    func test_newMilestones_crossesAll() {
        let crossed = GoalProgressCalculator.newMilestonesCrossed(from: 0.0, to: 1.0)
        XCTAssertEqual(crossed, [50, 75, 100])
    }

    // MARK: - Helpers

    private func makeGoal(current: Double, target: Double) -> Goal {
        Goal(
            id: UUID().uuidString,
            goalType: .dailyRevenue,
            targetValue: target,
            currentValue: current,
            period: .daily,
            startDate: base,
            endDate: base.addingTimeInterval(86400)
        )
    }
}
