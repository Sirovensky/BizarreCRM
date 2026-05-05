import XCTest
@testable import Inventory
import Networking

final class StocktakeDiscrepancyCalculatorTests: XCTestCase {

    // MARK: - discrepancies(from:)

    func test_discrepancies_noRows_returnsEmpty() {
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_discrepancies_allExact_returnsEmpty() {
        let rows = [
            row(sku: "A", expected: 10, actual: 10),
            row(sku: "B", expected: 5, actual: 5)
        ]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows)
        XCTAssertTrue(result.isEmpty)
    }

    func test_discrepancies_shortageDetected() {
        let rows = [
            row(sku: "A", expected: 10, actual: 8),
            row(sku: "B", expected: 5, actual: 5)
        ]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sku, "A")
        XCTAssertEqual(result[0].delta, -2)
        XCTAssertTrue(result[0].isShortage)
        XCTAssertFalse(result[0].isSurplus)
    }

    func test_discrepancies_surplusDetected() {
        let rows = [
            row(sku: "C", expected: 3, actual: 7)
        ]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].delta, 4)
        XCTAssertTrue(result[0].isSurplus)
    }

    func test_discrepancies_uncountedExcludedByDefault() {
        let rows = [
            row(sku: "X", expected: 5, actual: nil),
            row(sku: "Y", expected: 5, actual: 3)
        ]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows)
        // Only Y counts
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sku, "Y")
    }

    func test_discrepancies_uncountedTreatedAsZeroWhenFlagSet() {
        let rows = [
            row(sku: "X", expected: 5, actual: nil)
        ]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows, onlyCountedRows: false)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].actualQty, 0)
        XCTAssertEqual(result[0].delta, -5)
    }

    func test_discrepancies_zeroActualCountedIsDiscrepancy() {
        let rows = [row(sku: "Z", expected: 2, actual: 0)]
        let result = StocktakeDiscrepancyCalculator.discrepancies(from: rows)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].delta, -2)
    }

    // MARK: - summary(from:)

    func test_summary_emptyRows() {
        let s = StocktakeDiscrepancyCalculator.summary(from: [])
        XCTAssertEqual(s.totalRows, 0)
        XCTAssertEqual(s.countedRows, 0)
        XCTAssertEqual(s.discrepancyCount, 0)
        XCTAssertEqual(s.totalSurplus, 0)
        XCTAssertEqual(s.totalShortage, 0)
        XCTAssertEqual(s.netVariance, 0)
    }

    func test_summary_allCounted_noDiscrepancies() {
        let rows = [
            row(sku: "A", expected: 4, actual: 4),
            row(sku: "B", expected: 6, actual: 6)
        ]
        let s = StocktakeDiscrepancyCalculator.summary(from: rows)
        XCTAssertEqual(s.totalRows, 2)
        XCTAssertEqual(s.countedRows, 2)
        XCTAssertEqual(s.discrepancyCount, 0)
        XCTAssertEqual(s.totalSurplus, 0)
        XCTAssertEqual(s.totalShortage, 0)
        XCTAssertEqual(s.netVariance, 0)
    }

    func test_summary_mixedDiscrepancies() {
        let rows = [
            row(sku: "A", expected: 10, actual: 8),  // shortage 2
            row(sku: "B", expected: 5, actual: 7),   // surplus 2
            row(sku: "C", expected: 3, actual: 3),   // exact
            row(sku: "D", expected: 4, actual: nil)  // uncounted
        ]
        let s = StocktakeDiscrepancyCalculator.summary(from: rows)
        XCTAssertEqual(s.totalRows, 4)
        XCTAssertEqual(s.countedRows, 3)
        XCTAssertEqual(s.discrepancyCount, 2)
        XCTAssertEqual(s.totalSurplus, 2)
        XCTAssertEqual(s.totalShortage, 2)
        XCTAssertEqual(s.netVariance, 0)
    }

    func test_summary_onlySurplus() {
        let rows = [
            row(sku: "A", expected: 1, actual: 5),
            row(sku: "B", expected: 2, actual: 4)
        ]
        let s = StocktakeDiscrepancyCalculator.summary(from: rows)
        XCTAssertEqual(s.totalSurplus, 6)   // (5-1) + (4-2)
        XCTAssertEqual(s.totalShortage, 0)
        XCTAssertEqual(s.netVariance, 6)
    }

    func test_summary_onlyShortage() {
        let rows = [
            row(sku: "A", expected: 10, actual: 3),
            row(sku: "B", expected: 8, actual: 5)
        ]
        let s = StocktakeDiscrepancyCalculator.summary(from: rows)
        XCTAssertEqual(s.totalSurplus, 0)
        XCTAssertEqual(s.totalShortage, 10)  // (10-3) + (8-5)
        XCTAssertEqual(s.netVariance, -10)
    }

    // MARK: - StocktakeDiscrepancy model

    func test_discrepancy_deltaCalculation() {
        let d = StocktakeDiscrepancy(sku: "T1", name: "Test", expectedQty: 5, actualQty: 3)
        XCTAssertEqual(d.delta, -2)
        XCTAssertTrue(d.isShortage)
        XCTAssertFalse(d.isSurplus)
    }

    func test_discrepancy_surplusDelta() {
        let d = StocktakeDiscrepancy(sku: "T2", name: "Test", expectedQty: 2, actualQty: 9)
        XCTAssertEqual(d.delta, 7)
        XCTAssertTrue(d.isSurplus)
        XCTAssertFalse(d.isShortage)
    }

    func test_discrepancy_zeroDelta_isNeitherSurplusNorShortage() {
        let d = StocktakeDiscrepancy(sku: "T3", name: "Test", expectedQty: 5, actualQty: 5)
        XCTAssertEqual(d.delta, 0)
        XCTAssertFalse(d.isSurplus)
        XCTAssertFalse(d.isShortage)
    }

    // MARK: - Helpers

    private func row(sku: String, expected: Int, actual: Int?) -> StocktakeRow {
        StocktakeRow(id: Int64(sku.hashValue), sku: sku,
                     productName: sku, expectedQty: expected, actualQty: actual)
    }
}
