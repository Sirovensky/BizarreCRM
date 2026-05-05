import XCTest
@testable import Search

final class SearchFilterCalculatorTests: XCTestCase {

    // MARK: - buildQuery basics

    func test_buildQuery_emptyBase_emptyResult() {
        let result = SearchFilterCalculator.buildQuery(base: "", filters: SearchFilters())
        XCTAssertTrue(result.ftsQuery.isEmpty)
        XCTAssertTrue(result.isEmpty)
    }

    func test_buildQuery_baseOnly_noFilters() {
        let result = SearchFilterCalculator.buildQuery(base: "iphone", filters: SearchFilters())
        XCTAssertEqual(result.ftsQuery, "iphone")
    }

    func test_buildQuery_baseWithWhitespace_trimmed() {
        let result = SearchFilterCalculator.buildQuery(base: "  iphone  ", filters: SearchFilters())
        XCTAssertEqual(result.ftsQuery, "iphone")
    }

    // MARK: - Status filter

    func test_buildQuery_statusFilter_appendedWithAND() {
        let filters = SearchFilters(status: "in_progress")
        let result = SearchFilterCalculator.buildQuery(base: "screen", filters: filters)
        XCTAssertTrue(result.ftsQuery.contains("AND"), "Status filter should be ANDed")
        XCTAssertTrue(result.ftsQuery.contains("tags:"), "Status should target tags column")
    }

    func test_buildQuery_statusFilter_emptyStatus_notAdded() {
        let filters = SearchFilters(status: "")
        let result = SearchFilterCalculator.buildQuery(base: "iphone", filters: filters)
        XCTAssertFalse(result.ftsQuery.contains("tags:"))
    }

    func test_buildQuery_statusFilter_nilStatus_notAdded() {
        let filters = SearchFilters(status: nil)
        let result = SearchFilterCalculator.buildQuery(base: "iphone", filters: filters)
        XCTAssertFalse(result.ftsQuery.contains("tags:"))
    }

    func test_buildQuery_statusFilterOnly_noBase() {
        let filters = SearchFilters(status: "ready")
        let result = SearchFilterCalculator.buildQuery(base: "", filters: filters)
        // Base is empty; only status part
        XCTAssertTrue(result.ftsQuery.contains("tags:"))
    }

    // MARK: - Entity filter

    func test_buildQuery_entityFilter_returnsCorrectEnum() {
        let filters = SearchFilters(entity: .tickets)
        let result = SearchFilterCalculator.buildQuery(base: "crack", filters: filters)
        XCTAssertEqual(result.entityFilter, .tickets)
    }

    func test_buildQuery_defaultEntity_isAll() {
        let result = SearchFilterCalculator.buildQuery(base: "x", filters: SearchFilters())
        XCTAssertEqual(result.entityFilter, .all)
    }

    // MARK: - Date range pass-through

    func test_buildQuery_dateFrom_propagated() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let filters = SearchFilters(dateFrom: date)
        let result = SearchFilterCalculator.buildQuery(base: "x", filters: filters)
        XCTAssertEqual(result.dateFrom, date)
    }

    func test_buildQuery_dateTo_propagated() {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let filters = SearchFilters(dateTo: date)
        let result = SearchFilterCalculator.buildQuery(base: "x", filters: filters)
        XCTAssertEqual(result.dateTo, date)
    }

    func test_buildQuery_noDates_areBothNil() {
        let result = SearchFilterCalculator.buildQuery(base: "y", filters: SearchFilters())
        XCTAssertNil(result.dateFrom)
        XCTAssertNil(result.dateTo)
    }

    // MARK: - Special characters in status

    func test_buildQuery_statusWithQuote_escapedProperly() {
        let filters = SearchFilters(status: "status\"special")
        let result = SearchFilterCalculator.buildQuery(base: "q", filters: filters)
        // The result should not contain unescaped double-quote inside a phrase
        XCTAssertTrue(result.ftsQuery.contains("\"\""), "Quotes inside tags should be escaped")
    }
}
