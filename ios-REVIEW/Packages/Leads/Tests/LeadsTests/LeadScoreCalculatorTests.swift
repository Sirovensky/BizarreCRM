import XCTest
@testable import Leads

final class LeadScoreCalculatorTests: XCTestCase {

    // MARK: - Score bounds

    func test_score_neverBelow0() {
        let input = LeadScoreInput()
        let score = LeadScoreCalculator.compute(leadId: 1, input: input)
        XCTAssertGreaterThanOrEqual(score.score, 0)
    }

    func test_score_neverAbove100() {
        let input = LeadScoreInput(
            engagementCount: 100,
            daysSinceLastContact: 0,
            budgetCents: 1_000_000,
            daysUntilDeadline: 0,
            source: "referral"
        )
        let score = LeadScoreCalculator.compute(leadId: 1, input: input)
        XCTAssertLessThanOrEqual(score.score, 100)
    }

    // MARK: - Engagement factor

    func test_zeroEngagement_partialScore() {
        let none = LeadScoreInput(engagementCount: 0, source: nil)
        let five = LeadScoreInput(engagementCount: 5, source: nil)
        let scoreNone = LeadScoreCalculator.compute(leadId: 1, input: none).score
        let scoreFive = LeadScoreCalculator.compute(leadId: 1, input: five).score
        XCTAssertLessThan(scoreNone, scoreFive, "More engagement should yield higher score")
    }

    func test_engagement_capsAt5() {
        let five  = LeadScoreInput(engagementCount: 5,  source: nil)
        let fifty = LeadScoreInput(engagementCount: 50, source: nil)
        let scoreFive  = LeadScoreCalculator.compute(leadId: 1, input: five).score
        let scoreFifty = LeadScoreCalculator.compute(leadId: 1, input: fifty).score
        XCTAssertEqual(scoreFive, scoreFifty, "Engagement caps at 5 contacts")
    }

    // MARK: - Contact velocity factor

    func test_contactedToday_betterThan30Days() {
        let today = LeadScoreInput(daysSinceLastContact: 0)
        let old   = LeadScoreInput(daysSinceLastContact: 30)
        let scoreToday = LeadScoreCalculator.compute(leadId: 1, input: today).score
        let scoreOld   = LeadScoreCalculator.compute(leadId: 1, input: old).score
        XCTAssertGreaterThan(scoreToday, scoreOld)
    }

    func test_neverContacted_worseThanyesterday() {
        let never     = LeadScoreInput(daysSinceLastContact: nil)
        let yesterday = LeadScoreInput(daysSinceLastContact: 1)
        let scoreNever     = LeadScoreCalculator.compute(leadId: 1, input: never).score
        let scoreYesterday = LeadScoreCalculator.compute(leadId: 1, input: yesterday).score
        XCTAssertLessThan(scoreNever, scoreYesterday)
    }

    // MARK: - Budget factor

    func test_budgetPresent_raisesScore() {
        let noBudget   = LeadScoreInput(budgetCents: nil)
        let withBudget = LeadScoreInput(budgetCents: 50_000)
        let scoreNo   = LeadScoreCalculator.compute(leadId: 1, input: noBudget).score
        let scoreWith = LeadScoreCalculator.compute(leadId: 1, input: withBudget).score
        XCTAssertGreaterThan(scoreWith, scoreNo)
    }

    func test_zeroBudget_treatedAsNoBudget() {
        let zero = LeadScoreInput(budgetCents: 0)
        let nil_ = LeadScoreInput(budgetCents: nil)
        let scoreZero = LeadScoreCalculator.compute(leadId: 1, input: zero).score
        let scoreNil  = LeadScoreCalculator.compute(leadId: 1, input: nil_).score
        XCTAssertEqual(scoreZero, scoreNil)
    }

    // MARK: - Timeline urgency factor

    func test_shortDeadline_raisesScore() {
        let soon = LeadScoreInput(daysUntilDeadline: 5)
        let far  = LeadScoreInput(daysUntilDeadline: 60)
        let scoreSoon = LeadScoreCalculator.compute(leadId: 1, input: soon).score
        let scoreFar  = LeadScoreCalculator.compute(leadId: 1, input: far).score
        XCTAssertGreaterThan(scoreSoon, scoreFar)
    }

    func test_overdueDeadline_stillCounts() {
        let overdue    = LeadScoreInput(daysUntilDeadline: -1)
        let noDeadline = LeadScoreInput(daysUntilDeadline: nil)
        let scoreOverdue    = LeadScoreCalculator.compute(leadId: 1, input: overdue).score
        let scoreNoDeadline = LeadScoreCalculator.compute(leadId: 1, input: noDeadline).score
        XCTAssertGreaterThan(scoreOverdue, scoreNoDeadline)
    }

    // MARK: - Source quality factor

    func test_referral_highestSourceQuality() {
        XCTAssertEqual(LeadScoreCalculator.sourceQualityScore("referral"), 1.0)
    }

    func test_web_secondTierSource() {
        XCTAssertGreaterThan(
            LeadScoreCalculator.sourceQualityScore("web"),
            LeadScoreCalculator.sourceQualityScore("campaign")
        )
    }

    func test_unknownSource_lowestQuality() {
        XCTAssertLessThanOrEqual(
            LeadScoreCalculator.sourceQualityScore("mystery"),
            LeadScoreCalculator.sourceQualityScore("campaign")
        )
    }

    // MARK: - Factors list

    func test_computedScore_hasFactors() {
        let input = LeadScoreInput(engagementCount: 3)
        let result = LeadScoreCalculator.compute(leadId: 99, input: input)
        XCTAssertFalse(result.factors.isEmpty, "Factors list must not be empty")
    }

    func test_leadId_preserved() {
        let input = LeadScoreInput()
        let result = LeadScoreCalculator.compute(leadId: 42, input: input)
        XCTAssertEqual(result.leadId, 42)
    }

    // MARK: - LeadScore model

    func test_leadScore_clampsNegative() {
        let s = LeadScore(leadId: 1, score: -10, factors: [])
        XCTAssertEqual(s.score, 0)
    }

    func test_leadScore_clampsOver100() {
        let s = LeadScore(leadId: 1, score: 110, factors: [])
        XCTAssertEqual(s.score, 100)
    }

    func test_leadScore_exactBoundary30() {
        // score == 30 is Amber, not Red
        let s = LeadScore(leadId: 1, score: 30, factors: [])
        XCTAssertEqual(s.score, 30)
    }
}
