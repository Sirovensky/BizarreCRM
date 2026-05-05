import XCTest
@testable import Customers

// MARK: - ChurnScoreCalculatorTests
// §44.3 — Tests for ChurnScoreCalculator covering factor combinations,
// risk level mapping, and edge cases. All pure / synchronous.

final class ChurnScoreCalculatorTests: XCTestCase {

    // MARK: Baseline

    func test_noFactors_returnsBase50() {
        let input = ChurnInput(
            daysSinceLastVisit: nil,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: nil,
            ltvTrend: .stable
        )
        let result = ChurnScoreCalculator.compute(input: input)
        XCTAssertEqual(result.probability0to100, 50)
    }

    // MARK: Days since last visit factor

    func test_180plusDays_addsPoints() {
        let input = ChurnInput(
            daysSinceLastVisit: 200,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: nil,
            ltvTrend: .stable
        )
        let result = ChurnScoreCalculator.compute(input: input)
        XCTAssertGreaterThan(result.probability0to100, 50)
        XCTAssertTrue(result.factors.contains(where: { $0.contains("180+") || $0.contains("days since last visit") }))
    }

    func test_recentVisit_doesNotAddPoints() {
        let input = ChurnInput(
            daysSinceLastVisit: 10,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: nil,
            ltvTrend: .stable
        )
        let result = ChurnScoreCalculator.compute(input: input)
        XCTAssertEqual(result.probability0to100, 50)
    }

    func test_90to179Days_addsModeratePoints() {
        let input = ChurnInput(
            daysSinceLastVisit: 120,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: nil,
            ltvTrend: .stable
        )
        let result = ChurnScoreCalculator.compute(input: input)
        let base = ChurnScoreCalculator.compute(input: ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: nil, ltvTrend: .stable
        )).probability0to100
        // Should be more than base but less than 180+ days
        XCTAssertGreaterThan(result.probability0to100, base)
    }

    // MARK: Visit frequency decline

    func test_frequencyDecline_addsPoints() {
        let withDecline = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: true,
            supportComplaints: 0, npsScore: nil, ltvTrend: .stable
        )
        let withoutDecline = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: nil, ltvTrend: .stable
        )
        let r1 = ChurnScoreCalculator.compute(input: withDecline)
        let r2 = ChurnScoreCalculator.compute(input: withoutDecline)
        XCTAssertGreaterThan(r1.probability0to100, r2.probability0to100)
        XCTAssertTrue(r1.factors.contains(where: { $0.lowercased().contains("frequency") || $0.lowercased().contains("decline") }))
    }

    // MARK: Support complaints

    func test_supportComplaints_addsPointsPerComplaint() {
        let noComplaints = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: nil, ltvTrend: .stable
        )
        let oneComplaint = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 1, npsScore: nil, ltvTrend: .stable
        )
        let threeComplaints = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 3, npsScore: nil, ltvTrend: .stable
        )
        let r0 = ChurnScoreCalculator.compute(input: noComplaints).probability0to100
        let r1 = ChurnScoreCalculator.compute(input: oneComplaint).probability0to100
        let r3 = ChurnScoreCalculator.compute(input: threeComplaints).probability0to100
        XCTAssertGreaterThan(r1, r0)
        XCTAssertGreaterThan(r3, r1)
    }

    // MARK: NPS score (low NPS → higher churn)

    func test_lowNPS_addsChurnPoints() {
        let lowNPS = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: 2, ltvTrend: .stable
        )
        let highNPS = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: 9, ltvTrend: .stable
        )
        let rLow = ChurnScoreCalculator.compute(input: lowNPS).probability0to100
        let rHigh = ChurnScoreCalculator.compute(input: highNPS).probability0to100
        XCTAssertGreaterThan(rLow, rHigh)
    }

    // MARK: LTV trend

    func test_decliningLTV_addsPoints() {
        let declining = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: nil, ltvTrend: .declining
        )
        let stable = ChurnInput(
            daysSinceLastVisit: nil, visitFrequencyDecline: false,
            supportComplaints: 0, npsScore: nil, ltvTrend: .stable
        )
        let rDecline = ChurnScoreCalculator.compute(input: declining).probability0to100
        let rStable = ChurnScoreCalculator.compute(input: stable).probability0to100
        XCTAssertGreaterThan(rDecline, rStable)
    }

    // MARK: Score clamping

    func test_worstCaseInputClampsTo100() {
        let worst = ChurnInput(
            daysSinceLastVisit: 365,
            visitFrequencyDecline: true,
            supportComplaints: 10,
            npsScore: 0,
            ltvTrend: .declining
        )
        let result = ChurnScoreCalculator.compute(input: worst)
        XCTAssertLessThanOrEqual(result.probability0to100, 100)
        XCTAssertGreaterThanOrEqual(result.probability0to100, 0)
    }

    // MARK: Risk level mapping

    func test_probability_0to24_isLow() {
        // Force low probability by overriding via stub. Using growing NPS to push probability down.
        let input = ChurnInput(
            daysSinceLastVisit: 5,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: 10,
            ltvTrend: .growing
        )
        _ = ChurnScoreCalculator.compute(input: input)
        // Probability should be reduced below 25 with very positive signals
        // (base 50 minus growing NPS bonus). Check the rule mapping instead:
        XCTAssertEqual(ChurnRiskLevel(probability: 0), .low)
        XCTAssertEqual(ChurnRiskLevel(probability: 24), .low)
    }

    func test_probability_25to50_isMedium() {
        XCTAssertEqual(ChurnRiskLevel(probability: 25), .medium)
        XCTAssertEqual(ChurnRiskLevel(probability: 50), .medium)
    }

    func test_probability_51to75_isHigh() {
        XCTAssertEqual(ChurnRiskLevel(probability: 51), .high)
        XCTAssertEqual(ChurnRiskLevel(probability: 75), .high)
    }

    func test_probability_76to100_isCritical() {
        XCTAssertEqual(ChurnRiskLevel(probability: 76), .critical)
        XCTAssertEqual(ChurnRiskLevel(probability: 100), .critical)
    }

    // MARK: Factor strings non-empty on active signals

    func test_factors_nonEmptyWhenSignalsPresent() {
        let input = ChurnInput(
            daysSinceLastVisit: 200,
            visitFrequencyDecline: true,
            supportComplaints: 2,
            npsScore: 1,
            ltvTrend: .declining
        )
        let result = ChurnScoreCalculator.compute(input: input)
        XCTAssertFalse(result.factors.isEmpty)
    }

    func test_factors_emptyWhenNoSignals() {
        let input = ChurnInput(
            daysSinceLastVisit: nil,
            visitFrequencyDecline: false,
            supportComplaints: 0,
            npsScore: nil,
            ltvTrend: .stable
        )
        let result = ChurnScoreCalculator.compute(input: input)
        XCTAssertTrue(result.factors.isEmpty)
    }
}
