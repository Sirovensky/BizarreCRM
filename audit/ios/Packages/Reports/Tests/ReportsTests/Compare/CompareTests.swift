import XCTest
@testable import Reports

// MARK: - ComparePeriodTests

final class ComparePeriodTests: XCTestCase {

    // Reference interval: 30 days, starting 2024-01-01 00:00 UTC
    private let refStart = ISO8601DateFormatter.fullDate.date(from: "2024-01-01")!
    private var refInterval: DateInterval {
        DateInterval(start: refStart, duration: 30 * 86400)
    }

    // MARK: - displayLabel

    func test_previousWeek_displayLabel() {
        XCTAssertEqual(ComparePeriod.previousWeek.displayLabel, "Prev Week")
    }

    func test_previousMonth_displayLabel() {
        XCTAssertEqual(ComparePeriod.previousMonth.displayLabel, "Prev Month")
    }

    func test_previousYear_displayLabel() {
        XCTAssertEqual(ComparePeriod.previousYear.displayLabel, "Prev Year")
    }

    func test_custom_displayLabel() {
        let di = DateInterval(start: refStart, duration: 7 * 86400)
        XCTAssertEqual(ComparePeriod.custom(di).displayLabel, "Custom")
    }

    // MARK: - priorInterval duration preservation

    func test_previousWeek_preservesDuration() {
        let prior = ComparePeriod.previousWeek.priorInterval(relativeTo: refInterval)
        XCTAssertEqual(prior.duration, refInterval.duration, accuracy: 1)
    }

    func test_previousMonth_preservesDuration() {
        let prior = ComparePeriod.previousMonth.priorInterval(relativeTo: refInterval)
        XCTAssertEqual(prior.duration, refInterval.duration, accuracy: 1)
    }

    func test_previousYear_preservesDuration() {
        let prior = ComparePeriod.previousYear.priorInterval(relativeTo: refInterval)
        XCTAssertEqual(prior.duration, refInterval.duration, accuracy: 1)
    }

    // MARK: - priorInterval shift correctness

    func test_previousWeek_shiftsBy7Days() {
        let prior = ComparePeriod.previousWeek.priorInterval(relativeTo: refInterval)
        let expectedStart = refStart.addingTimeInterval(-7 * 86400)
        XCTAssertEqual(prior.start.timeIntervalSince1970,
                       expectedStart.timeIntervalSince1970,
                       accuracy: 1)
    }

    func test_previousMonth_shiftsBy30Days() {
        let prior = ComparePeriod.previousMonth.priorInterval(relativeTo: refInterval)
        let expectedStart = refStart.addingTimeInterval(-30 * 86400)
        XCTAssertEqual(prior.start.timeIntervalSince1970,
                       expectedStart.timeIntervalSince1970,
                       accuracy: 1)
    }

    func test_previousYear_shiftsBy365Days() {
        let prior = ComparePeriod.previousYear.priorInterval(relativeTo: refInterval)
        let expectedStart = refStart.addingTimeInterval(-365 * 86400)
        XCTAssertEqual(prior.start.timeIntervalSince1970,
                       expectedStart.timeIntervalSince1970,
                       accuracy: 1)
    }

    func test_custom_returnsStoredInterval() {
        let custom = DateInterval(start: refStart.addingTimeInterval(-100 * 86400), duration: 14 * 86400)
        let prior = ComparePeriod.custom(custom).priorInterval(relativeTo: refInterval)
        XCTAssertEqual(prior, custom)
    }

    // MARK: - priorDateStrings

    func test_previousWeek_priorDateStrings_fromIsBeforeCurrentFrom() {
        let (from, _) = ComparePeriod.previousWeek.priorDateStrings(relativeTo: refInterval)
        let priorFromDate = ISO8601DateFormatter.fullDate.date(from: from)!
        XCTAssertLessThan(priorFromDate, refStart)
    }

    func test_previousMonth_priorDateStrings_returnsValidISO8601() {
        let (from, to) = ComparePeriod.previousMonth.priorDateStrings(relativeTo: refInterval)
        XCTAssertNotNil(ISO8601DateFormatter.fullDate.date(from: from))
        XCTAssertNotNil(ISO8601DateFormatter.fullDate.date(from: to))
    }

    func test_previousYear_priorDateStrings_fromIs365DaysBefore() {
        let (from, _) = ComparePeriod.previousYear.priorDateStrings(relativeTo: refInterval)
        let priorFromDate = ISO8601DateFormatter.fullDate.date(from: from)!
        let expectedFrom = refStart.addingTimeInterval(-365 * 86400)
        XCTAssertEqual(priorFromDate.timeIntervalSince1970,
                       expectedFrom.timeIntervalSince1970,
                       accuracy: 86400) // within one day (date-only precision)
    }

    // MARK: - Equatable

    func test_sameCase_isEqual() {
        XCTAssertEqual(ComparePeriod.previousWeek, ComparePeriod.previousWeek)
        XCTAssertEqual(ComparePeriod.previousMonth, ComparePeriod.previousMonth)
        XCTAssertEqual(ComparePeriod.previousYear, ComparePeriod.previousYear)
    }

    func test_differentCases_areNotEqual() {
        XCTAssertNotEqual(ComparePeriod.previousWeek, ComparePeriod.previousMonth)
        XCTAssertNotEqual(ComparePeriod.previousMonth, ComparePeriod.previousYear)
    }

    func test_customWithSameInterval_isEqual() {
        let di = DateInterval(start: refStart, duration: 7 * 86400)
        XCTAssertEqual(ComparePeriod.custom(di), ComparePeriod.custom(di))
    }

    func test_customWithDifferentInterval_isNotEqual() {
        let di1 = DateInterval(start: refStart, duration: 7 * 86400)
        let di2 = DateInterval(start: refStart, duration: 14 * 86400)
        XCTAssertNotEqual(ComparePeriod.custom(di1), ComparePeriod.custom(di2))
    }

    // MARK: - Hashable (used in SwiftUI Picker tag)

    func test_hashableConsistency() {
        var seen = Set<ComparePeriod>()
        seen.insert(.previousWeek)
        seen.insert(.previousMonth)
        seen.insert(.previousYear)
        let di = DateInterval(start: refStart, duration: 7 * 86400)
        seen.insert(.custom(di))
        XCTAssertEqual(seen.count, 4)
    }
}

// MARK: - ComparisonVarianceTests

final class ComparisonVarianceTests: XCTestCase {

    // MARK: - percentChange

    func test_positiveGrowth() {
        let pct = ComparisonVariance.percentChange(current: 120, prior: 100)
        XCTAssertEqual(pct!, 20.0, accuracy: 0.001)
    }

    func test_negativeGrowth() {
        let pct = ComparisonVariance.percentChange(current: 80, prior: 100)
        XCTAssertEqual(pct!, -20.0, accuracy: 0.001)
    }

    func test_noChange_returnsZero() {
        let pct = ComparisonVariance.percentChange(current: 100, prior: 100)
        XCTAssertEqual(pct!, 0.0, accuracy: 0.001)
    }

    func test_priorZero_returnsNil() {
        XCTAssertNil(ComparisonVariance.percentChange(current: 50, prior: 0))
    }

    func test_currentZero_prior100_returns_neg100() {
        let pct = ComparisonVariance.percentChange(current: 0, prior: 100)
        XCTAssertEqual(pct!, -100.0, accuracy: 0.001)
    }

    func test_negativePrior_absoluteValueUsed() {
        // prior = -100 → abs(prior) = 100; current = -80 → change = ((-80) - (-100)) / 100 = 20%
        let pct = ComparisonVariance.percentChange(current: -80, prior: -100)
        XCTAssertEqual(pct!, 20.0, accuracy: 0.001)
    }

    func test_smallFractional_accuracy() {
        let pct = ComparisonVariance.percentChange(current: 1.005, prior: 1.000)
        XCTAssertEqual(pct!, 0.5, accuracy: 0.001)
    }

    // MARK: - variance (VarianceResult)

    func test_variance_positiveGrowth_directionUp() {
        let r = ComparisonVariance.variance(current: 150, prior: 100)
        XCTAssertEqual(r.direction, .up)
        XCTAssertEqual(r.pct!, 50.0, accuracy: 0.001)
    }

    func test_variance_negativeGrowth_directionDown() {
        let r = ComparisonVariance.variance(current: 50, prior: 100)
        XCTAssertEqual(r.direction, .down)
        XCTAssertEqual(r.pct!, -50.0, accuracy: 0.001)
    }

    func test_variance_noChange_directionFlat() {
        let r = ComparisonVariance.variance(current: 100, prior: 100)
        XCTAssertEqual(r.direction, .flat)
        XCTAssertEqual(r.pct!, 0.0, accuracy: 0.001)
    }

    func test_variance_priorZero_pctNil_directionUp_whenPositiveCurrent() {
        let r = ComparisonVariance.variance(current: 42, prior: 0)
        XCTAssertNil(r.pct)
        XCTAssertEqual(r.direction, .up)
    }

    func test_variance_priorZero_currentAlsoZero_directionFlat() {
        let r = ComparisonVariance.variance(current: 0, prior: 0)
        XCTAssertNil(r.pct)
        XCTAssertEqual(r.direction, .flat)
    }

    func test_variance_priorZero_currentNegative_directionDown() {
        let r = ComparisonVariance.variance(current: -5, prior: 0)
        XCTAssertNil(r.pct)
        XCTAssertEqual(r.direction, .down)
    }

    // MARK: - alignedVariance

    func test_alignedVariance_equalLengthArrays() {
        let current = [110.0, 90.0, 100.0]
        let prior   = [100.0, 100.0, 100.0]
        let result  = ComparisonVariance.alignedVariance(current: current, prior: prior)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].pct!, 10.0, accuracy: 0.001)
        XCTAssertEqual(result[1].pct!, -10.0, accuracy: 0.001)
        XCTAssertEqual(result[2].pct!, 0.0, accuracy: 0.001)
    }

    func test_alignedVariance_currentLonger_trims() {
        let result = ComparisonVariance.alignedVariance(
            current: [100, 200, 300, 400],
            prior:   [50,  100]
        )
        XCTAssertEqual(result.count, 2)
    }

    func test_alignedVariance_priorLonger_trims() {
        let result = ComparisonVariance.alignedVariance(
            current: [50],
            prior:   [100, 200, 300]
        )
        XCTAssertEqual(result.count, 1)
    }

    func test_alignedVariance_emptyArrays_returnsEmpty() {
        let result = ComparisonVariance.alignedVariance(current: [], prior: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_alignedVariance_priorContainsZero_pctNilForThatPoint() {
        let result = ComparisonVariance.alignedVariance(
            current: [100, 200],
            prior:   [0,   100]
        )
        XCTAssertNil(result[0].pct)
        XCTAssertEqual(result[1].pct!, 100.0, accuracy: 0.001)
    }

    func test_alignedVariance_indexesAreSequential() {
        let result = ComparisonVariance.alignedVariance(
            current: [1, 2, 3],
            prior:   [1, 2, 3]
        )
        XCTAssertEqual(result.map(\.index), [0, 1, 2])
    }

    func test_alignedVariance_currentAndPriorValuesPreserved() {
        let result = ComparisonVariance.alignedVariance(
            current: [250.5],
            prior:   [200.0]
        )
        XCTAssertEqual(result[0].currentValue, 250.5, accuracy: 0.001)
        XCTAssertEqual(result[0].priorValue,   200.0, accuracy: 0.001)
    }

    // MARK: - AlignedPoint equatable

    func test_alignedPoint_equality() {
        let a = AlignedPoint(index: 0, currentValue: 10, priorValue: 5, pct: 100)
        let b = AlignedPoint(index: 0, currentValue: 10, priorValue: 5, pct: 100)
        XCTAssertEqual(a, b)
    }

    // MARK: - VarianceDirection equatable

    func test_varianceDirection_equality() {
        XCTAssertEqual(VarianceDirection.up,   .up)
        XCTAssertEqual(VarianceDirection.down, .down)
        XCTAssertEqual(VarianceDirection.flat, .flat)
        XCTAssertNotEqual(VarianceDirection.up, .down)
    }

    // MARK: - VarianceResult equatable

    func test_varianceResult_equality() {
        let a = VarianceResult(pct: 10.0, direction: .up)
        let b = VarianceResult(pct: 10.0, direction: .up)
        XCTAssertEqual(a, b)
    }

    func test_varianceResult_nilPct_equality() {
        let a = VarianceResult(pct: nil, direction: .flat)
        let b = VarianceResult(pct: nil, direction: .flat)
        XCTAssertEqual(a, b)
    }
}
