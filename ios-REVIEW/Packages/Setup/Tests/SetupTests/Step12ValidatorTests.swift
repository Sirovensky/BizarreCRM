import XCTest
@testable import Setup

final class Step12ValidatorTests: XCTestCase {

    // MARK: - isNextEnabled (always true)

    func testIsNextEnabled_nilSource_true() {
        XCTAssertTrue(Step12Validator.isNextEnabled(source: nil))
    }

    func testIsNextEnabled_skip_true() {
        XCTAssertTrue(Step12Validator.isNextEnabled(source: .skip))
    }

    func testIsNextEnabled_repairDesk_true() {
        XCTAssertTrue(Step12Validator.isNextEnabled(source: .repairDesk))
    }

    func testIsNextEnabled_csv_true() {
        XCTAssertTrue(Step12Validator.isNextEnabled(source: .csv))
    }

    // MARK: - ImportSource metadata

    func testImportSource_allCasesHaveNonEmptyDisplayName() {
        for source in ImportSource.allCases {
            XCTAssertFalse(source.displayName.isEmpty, "\(source) has empty displayName")
        }
    }

    func testImportSource_rawValues_areDistinct() {
        let rawValues = ImportSource.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    func testImportSource_skipRawValue() {
        XCTAssertEqual(ImportSource.skip.rawValue, "skip")
    }
}
