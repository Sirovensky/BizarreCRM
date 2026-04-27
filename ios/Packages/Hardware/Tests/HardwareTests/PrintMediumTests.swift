import XCTest
@testable import Hardware

// MARK: - PrintMediumTests

final class PrintMediumTests: XCTestCase {

    // MARK: - contentWidth

    func test_thermal80mm_contentWidth_isPositive() {
        XCTAssertGreaterThan(PrintMedium.thermal80mm.contentWidth, 0)
    }

    func test_thermal58mm_contentWidth_isNarrowerThan80mm() {
        XCTAssertLessThan(PrintMedium.thermal58mm.contentWidth, PrintMedium.thermal80mm.contentWidth)
    }

    func test_letter_contentWidth_isWiderThan80mm() {
        XCTAssertGreaterThan(PrintMedium.letter.contentWidth, PrintMedium.thermal80mm.contentWidth)
    }

    func test_a4_contentWidth_isWiderThan80mm() {
        XCTAssertGreaterThan(PrintMedium.a4.contentWidth, PrintMedium.thermal80mm.contentWidth)
    }

    func test_label4x6_contentWidth_equals288() {
        XCTAssertEqual(PrintMedium.label4x6.contentWidth, 288)
    }

    func test_label2x4_contentWidth_equals144() {
        XCTAssertEqual(PrintMedium.label2x4.contentWidth, 144)
    }

    // MARK: - pageWidth ≥ contentWidth

    func test_allCases_pageWidthAtLeastContentWidth() {
        for medium in PrintMedium.allCases {
            XCTAssertGreaterThanOrEqual(
                medium.pageWidth,
                medium.contentWidth,
                "\(medium.rawValue): pageWidth must be ≥ contentWidth"
            )
        }
    }

    // MARK: - sideMargin ≥ 0

    func test_allCases_sideMarginNonNegative() {
        for medium in PrintMedium.allCases {
            XCTAssertGreaterThanOrEqual(
                medium.sideMargin,
                0,
                "\(medium.rawValue): sideMargin must be non-negative"
            )
        }
    }

    // MARK: - displayName

    func test_allCases_displayNameNonEmpty() {
        for medium in PrintMedium.allCases {
            XCTAssertFalse(medium.displayName.isEmpty,
                           "\(medium.rawValue) must have a non-empty displayName")
        }
    }

    func test_thermal80mm_displayName_contains80() {
        XCTAssertTrue(PrintMedium.thermal80mm.displayName.contains("80"))
    }

    func test_thermal58mm_displayName_contains58() {
        XCTAssertTrue(PrintMedium.thermal58mm.displayName.contains("58"))
    }

    // MARK: - twoColumnLineItems

    func test_letter_isTwoColumn() {
        XCTAssertTrue(PrintMedium.letter.twoColumnLineItems)
    }

    func test_a4_isTwoColumn() {
        XCTAssertTrue(PrintMedium.a4.twoColumnLineItems)
    }

    func test_thermal80mm_isNotTwoColumn() {
        XCTAssertFalse(PrintMedium.thermal80mm.twoColumnLineItems)
    }

    func test_thermal58mm_isNotTwoColumn() {
        XCTAssertFalse(PrintMedium.thermal58mm.twoColumnLineItems)
    }

    // MARK: - CaseIterable

    func test_allCases_hasSevenCases() {
        XCTAssertEqual(PrintMedium.allCases.count, 7)
    }

    func test_legal_isTwoColumn() {
        XCTAssertTrue(PrintMedium.legal.twoColumnLineItems)
    }

    func test_legal_displayName_containsLegal() {
        XCTAssertTrue(PrintMedium.legal.displayName.lowercased().contains("legal"))
    }

    func test_legal_pageHeight_equals1008() {
        XCTAssertEqual(PrintMedium.legal.pageHeight, 1008)
    }

    func test_tenantDefault_isNotNil() {
        let def = PrintMedium.tenantDefault
        XCTAssertTrue(PrintMedium.allCases.contains(def))
    }

    func test_rawValues_areUnique() {
        let rawValues = PrintMedium.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        XCTAssertEqual(rawValues.count, unique.count, "All rawValues must be unique")
    }

    // MARK: - Ordering sanity: thermal80 narrower than letter

    func test_widthOrdering_thermal80_letter_a4() {
        let w80 = PrintMedium.thermal80mm.contentWidth
        let wLetter = PrintMedium.letter.contentWidth
        let wA4 = PrintMedium.a4.contentWidth
        XCTAssertLessThan(w80, wLetter)
        XCTAssertLessThan(w80, wA4)
    }
}
