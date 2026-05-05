import XCTest
@testable import Setup

final class Step12aValidatorTests: XCTestCase {

    // MARK: - validate

    func testValidate_system_valid() {
        XCTAssertTrue(Step12aValidator.validate(.system).isValid)
    }

    func testValidate_dark_valid() {
        XCTAssertTrue(Step12aValidator.validate(.dark).isValid)
    }

    func testValidate_light_valid() {
        XCTAssertTrue(Step12aValidator.validate(.light).isValid)
    }

    // MARK: - isNextEnabled

    func testIsNextEnabled_allChoices_true() {
        for choice in AppThemeChoice.allCases {
            XCTAssertTrue(Step12aValidator.isNextEnabled(theme: choice),
                          "\(choice) should always be next-enabled")
        }
    }

    // MARK: - AppThemeChoice metadata

    func testAppThemeChoice_rawValues_matchStrings() {
        XCTAssertEqual(AppThemeChoice.system.rawValue, "system")
        XCTAssertEqual(AppThemeChoice.dark.rawValue,   "dark")
        XCTAssertEqual(AppThemeChoice.light.rawValue,  "light")
    }

    func testAppThemeChoice_allCasesHaveNonEmptyDisplayName() {
        for choice in AppThemeChoice.allCases {
            XCTAssertFalse(choice.displayName.isEmpty, "\(choice) has empty displayName")
        }
    }

    func testAppThemeChoice_systemDisplayNameContainsRecommended() {
        XCTAssertTrue(AppThemeChoice.system.displayName.lowercased().contains("recommended"))
    }

    func testAppThemeChoice_exactlyThreeCases() {
        XCTAssertEqual(AppThemeChoice.allCases.count, 3)
    }
}
