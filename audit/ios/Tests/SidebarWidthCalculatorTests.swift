import XCTest
@testable import BizarreCRM   // App module; SidebarWidthBehavior lives here

// MARK: - SidebarWidthCalculatorTests

/// Unit tests for `SidebarWidthCalculator`.
///
/// Coverage target: ≥ 80 % (all three `SidebarWidth` branches exercised).
/// Tests are pure-value; no UIKit, no async, no network.
final class SidebarWidthCalculatorTests: XCTestCase {

    // MARK: - width(for:) — category mapping

    func test_width_belowCompactThreshold_returnsCompact() {
        // 599 pt is strictly below the 600 pt boundary.
        XCTAssertEqual(SidebarWidthCalculator.width(for: 599), .compact)
    }

    func test_width_atZero_returnsCompact() {
        XCTAssertEqual(SidebarWidthCalculator.width(for: 0), .compact)
    }

    func test_width_atCompactRegularBoundary_returnsRegular() {
        // 600 pt is the first value in the regular range.
        XCTAssertEqual(SidebarWidthCalculator.width(for: 600), .regular)
    }

    func test_width_midRegular_returnsRegular() {
        XCTAssertEqual(SidebarWidthCalculator.width(for: 800), .regular)
    }

    func test_width_justBeforeExpanded_returnsRegular() {
        // 999 pt is still inside regular range.
        XCTAssertEqual(SidebarWidthCalculator.width(for: 999), .regular)
    }

    func test_width_atExpandedThreshold_returnsExpanded() {
        // 1000 pt is the first value in the expanded range.
        XCTAssertEqual(SidebarWidthCalculator.width(for: 1000), .expanded)
    }

    func test_width_largeValue_returnsExpanded() {
        XCTAssertEqual(SidebarWidthCalculator.width(for: 1366), .expanded)
    }

    // MARK: - recommendedSidebarWidth(for:) — value tuples

    func test_recommendedWidthCompact_matchesSpec() {
        let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: .compact)
        XCTAssertEqual(rec.min,   240)
        XCTAssertEqual(rec.ideal, 260)
        XCTAssertEqual(rec.max,   280)
    }

    func test_recommendedWidthRegular_matchesSpec() {
        let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: .regular)
        XCTAssertEqual(rec.min,   260)
        XCTAssertEqual(rec.ideal, 300)
        XCTAssertEqual(rec.max,   340)
    }

    func test_recommendedWidthExpanded_matchesSpec() {
        let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: .expanded)
        XCTAssertEqual(rec.min,   320)
        XCTAssertEqual(rec.ideal, 360)
        XCTAssertEqual(rec.max,   400)
    }

    // MARK: - Ordering invariants

    func test_allCategories_minLessThanIdeal() {
        for cat in [SidebarWidth.compact, .regular, .expanded] {
            let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: cat)
            XCTAssertLessThan(rec.min, rec.ideal, "min < ideal for \(cat)")
        }
    }

    func test_allCategories_idealLessThanMax() {
        for cat in [SidebarWidth.compact, .regular, .expanded] {
            let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: cat)
            XCTAssertLessThan(rec.ideal, rec.max, "ideal < max for \(cat)")
        }
    }

    // MARK: - Round-trip consistency

    func test_roundTrip_compactWidth_givesCompactRec() {
        let category = SidebarWidthCalculator.width(for: 400)
        let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: category)
        // Sanity: compact rec max is 280, which is less than 600.
        XCTAssertLessThan(rec.max, 600)
    }

    func test_roundTrip_expandedWidth_givesLargestRec() {
        let category = SidebarWidthCalculator.width(for: 1200)
        let rec = SidebarWidthCalculator.recommendedSidebarWidth(for: category)
        XCTAssertEqual(rec.ideal, 360)
    }
}
