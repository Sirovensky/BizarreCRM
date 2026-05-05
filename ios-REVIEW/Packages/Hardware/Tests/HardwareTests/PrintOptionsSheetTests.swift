import XCTest
@testable import Hardware

// MARK: - PrintOptionsSheetTests
//
// §17 Reprint options: printer choice, paper size, copies, reason.

final class PrintOptionsSheetTests: XCTestCase {

    // MARK: - PrintOptions init

    func test_printOptions_copiesclamped_min1() {
        let opts = PrintOptions(selectedPrinter: nil, paperSize: .thermal80mm, copies: 0)
        XCTAssertEqual(opts.copies, 1)
    }

    func test_printOptions_copiesclamped_negative() {
        let opts = PrintOptions(selectedPrinter: nil, paperSize: .letter, copies: -5)
        XCTAssertEqual(opts.copies, 1)
    }

    func test_printOptions_validCopies() {
        let opts = PrintOptions(selectedPrinter: nil, paperSize: .a4, copies: 5)
        XCTAssertEqual(opts.copies, 5)
    }

    func test_printOptions_paperSizePreserved() {
        let opts = PrintOptions(selectedPrinter: nil, paperSize: .legal, copies: 1)
        XCTAssertEqual(opts.paperSize, .legal)
    }

    func test_printOptions_reasonIsNilByDefault() {
        let opts = PrintOptions(selectedPrinter: nil, paperSize: .thermal80mm, copies: 1)
        XCTAssertNil(opts.reason)
    }

    // MARK: - ReprintReason

    func test_reprintReason_allCases_haveNonEmptyRawValues() {
        for reason in ReprintReason.allCases {
            XCTAssertFalse(reason.rawValue.isEmpty, "\(reason) must have a non-empty rawValue")
        }
    }

    func test_reprintReason_idEqualsRawValue() {
        for reason in ReprintReason.allCases {
            XCTAssertEqual(reason.id, reason.rawValue)
        }
    }

    func test_reprintReason_hasAtLeastThreeCases() {
        XCTAssertGreaterThanOrEqual(ReprintReason.allCases.count, 3)
    }

    func test_reprintReason_customerLostIt_exists() {
        XCTAssertNotNil(ReprintReason(rawValue: "Customer lost it"))
    }

    // MARK: - PrintOptions with reason

    func test_printOptions_withReason_preserved() {
        let opts = PrintOptions(
            selectedPrinter: nil,
            paperSize: .thermal80mm,
            copies: 1,
            reason: .auditRequest
        )
        XCTAssertEqual(opts.reason, .auditRequest)
    }
}
