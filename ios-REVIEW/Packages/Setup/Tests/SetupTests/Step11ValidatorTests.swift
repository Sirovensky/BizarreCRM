import XCTest
@testable import Setup

final class Step11ValidatorTests: XCTestCase {

    // MARK: - isNextEnabled (always true — skippable)

    func testIsNextEnabled_emptySelection_true() {
        XCTAssertTrue(Step11Validator.isNextEnabled(selected: []))
    }

    func testIsNextEnabled_oneFamily_true() {
        XCTAssertTrue(Step11Validator.isNextEnabled(selected: [.iPhone]))
    }

    func testIsNextEnabled_allFamilies_true() {
        XCTAssertTrue(Step11Validator.isNextEnabled(selected: Set(DeviceFamily.allCases)))
    }

    // MARK: - DeviceFamily metadata

    func testDeviceFamily_allCasesHaveNonEmptyDisplayName() {
        for family in DeviceFamily.allCases {
            XCTAssertFalse(family.displayName.isEmpty, "\(family) has empty displayName")
        }
    }

    func testDeviceFamily_allCasesHaveNonEmptySystemImage() {
        for family in DeviceFamily.allCases {
            XCTAssertFalse(family.systemImage.isEmpty, "\(family) has empty systemImage")
        }
    }

    func testDeviceFamily_customHasZeroModels() {
        XCTAssertEqual(DeviceFamily.custom.preloadedModelCount, 0)
    }

    func testDeviceFamily_iPhoneHasModels() {
        XCTAssertGreaterThan(DeviceFamily.iPhone.preloadedModelCount, 0)
    }

    func testDeviceFamily_rawValues_areDistinct() {
        let rawValues = DeviceFamily.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }
}
