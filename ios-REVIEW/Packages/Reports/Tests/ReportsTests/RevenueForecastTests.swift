import XCTest
@testable import Reports

// §59.3 RevenueForecaster — linear regression + forecast point tests

final class RevenueForecastTests: XCTestCase {

    // MARK: - linearRegression

    func testLinearRegression_perfectLine() {
        // y = 2x + 1
        let points: [(Double, Double)] = [
            (1, 3), (2, 5), (3, 7), (4, 9)
        ]
        let result = RevenueForecaster.linearRegression(points: points)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope, 2.0, accuracy: 1e-6)
        XCTAssertEqual(result!.intercept, 1.0, accuracy: 1e-6)
    }

    func testLinearRegression_horizontalLine_returnsZeroSlope() {
        // y = 5 for all x
        let points: [(Double, Double)] = [(1, 5), (2, 5), (3, 5)]
        let result = RevenueForecaster.linearRegression(points: points)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.slope, 0.0, accuracy: 1e-6)
        XCTAssertEqual(result!.intercept, 5.0, accuracy: 1e-6)
    }

    func testLinearRegression_singleXValue_returnsNil() {
        // All x identical → denominator = 0 → nil
        let points: [(Double, Double)] = [(1, 3), (1, 5), (1, 7)]
        let result = RevenueForecaster.linearRegression(points: points)
        XCTAssertNil(result, "Should return nil when x values have zero variance")
    }

    // MARK: - forecast (insufficient data)

    func testForecast_fewerThan3Points_returnsEmpty() {
        let now = Date()
        let cashFlow = (0..<2).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .day, value: -(i * 30), to: now)!,
                inflowCents: 100_000,
                outflowCents: 50_000
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        XCTAssertTrue(result.isEmpty, "Need ≥3 points; should return empty for 2")
    }

    func testForecast_exactlyThreePoints_returns3ForecastPoints() {
        let now = Date()
        let cashFlow = (0..<3).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .month, value: -(3 - i), to: now)!,
                inflowCents: (i + 1) * 100_000,
                outflowCents: 20_000
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        XCTAssertEqual(result.count, 3, "Should return 3 forecast points (30/60/90d)")
    }

    func testForecast_pointsHavePositiveProjections() {
        let now = Date()
        let cashFlow = (0..<5).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .month, value: -(5 - i), to: now)!,
                inflowCents: (i + 1) * 50_000,
                outflowCents: 10_000
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        for point in result {
            XCTAssertGreaterThan(point.projectedCents, 0, "Projected value should be positive")
            XCTAssertLessThanOrEqual(point.lowerBoundCents, point.projectedCents, "Lower bound ≤ projection")
            XCTAssertGreaterThanOrEqual(point.upperBoundCents, point.projectedCents, "Upper bound ≥ projection")
        }
    }

    func testForecast_datesAreMonotonicallyIncreasing() {
        let now = Date()
        let cashFlow = (0..<4).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .month, value: -(4 - i), to: now)!,
                inflowCents: 80_000,
                outflowCents: 20_000
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        XCTAssertEqual(result.count, 3)
        XCTAssertLessThan(result[0].date, result[1].date)
        XCTAssertLessThan(result[1].date, result[2].date)
    }

    func testForecast_90dPointHasLaterDateThan30d() {
        let now = Date()
        let cashFlow = (0..<4).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .month, value: -(4 - i), to: now)!,
                inflowCents: 60_000,
                outflowCents: 15_000
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        guard result.count == 3 else { return }
        let diff = result[2].date.timeIntervalSince(result[0].date)
        XCTAssertGreaterThan(diff, 0, "90d point must be after 30d point")
    }

    func testForecast_lowerBoundNeverNegative() {
        // With near-zero revenue, lower bound should still be ≥ 0
        let now = Date()
        let cashFlow = (0..<3).map { i -> CashFlowPoint in
            CashFlowPoint(
                id: "\(i)",
                date: Calendar.current.date(byAdding: .month, value: -(3 - i), to: now)!,
                inflowCents: 1_000,
                outflowCents: 500
            )
        }
        let result = RevenueForecaster.forecast(from: cashFlow)
        for p in result {
            XCTAssertGreaterThanOrEqual(p.lowerBoundCents, 0, "Lower bound must not be negative")
            XCTAssertGreaterThanOrEqual(p.upperBoundCents, 0, "Upper bound must not be negative")
            XCTAssertGreaterThanOrEqual(p.projectedCents, 0, "Projected cents must not be negative")
        }
    }

    func testForecast_emptyInput_returnsEmpty() {
        let result = RevenueForecaster.forecast(from: [])
        XCTAssertTrue(result.isEmpty, "Empty input → empty forecast")
    }
}
