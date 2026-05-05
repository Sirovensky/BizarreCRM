import XCTest
@testable import Core

// §28 Security & Privacy helpers — DataHandlingCategory tests

final class DataHandlingCategoriesTests: XCTestCase {

    // MARK: - SensitivityLevel ordering

    func test_sensitivityLevel_ordering() {
        XCTAssertLessThan(SensitivityLevel.low, .medium)
        XCTAssertLessThan(SensitivityLevel.medium, .high)
        XCTAssertLessThan(SensitivityLevel.high, .critical)
    }

    func test_sensitivityLevel_equality() {
        XCTAssertEqual(SensitivityLevel.high, .high)
        XCTAssertNotEqual(SensitivityLevel.low, .critical)
    }

    // MARK: - sensitivityLevel per category

    func test_paymentCard_isCritical() {
        XCTAssertEqual(DataHandlingCategory.paymentCard.sensitivityLevel, .critical)
    }

    func test_email_isHigh() {
        XCTAssertEqual(DataHandlingCategory.email.sensitivityLevel, .high)
    }

    func test_phone_isHigh() {
        XCTAssertEqual(DataHandlingCategory.phone.sensitivityLevel, .high)
    }

    func test_address_isHigh() {
        XCTAssertEqual(DataHandlingCategory.address.sensitivityLevel, .high)
    }

    func test_name_isMedium() {
        XCTAssertEqual(DataHandlingCategory.name.sensitivityLevel, .medium)
    }

    func test_deviceID_isMedium() {
        XCTAssertEqual(DataHandlingCategory.deviceID.sensitivityLevel, .medium)
    }

    func test_locationCoarse_isLow() {
        XCTAssertEqual(DataHandlingCategory.locationCoarse.sensitivityLevel, .low)
    }

    // MARK: - displayName

    func test_displayNames_areNonEmpty() {
        for category in DataHandlingCategory.allCases {
            XCTAssertFalse(
                category.displayName.isEmpty,
                "\(category) must have a non-empty displayName"
            )
        }
    }

    func test_displayName_paymentCard() {
        XCTAssertEqual(DataHandlingCategory.paymentCard.displayName, "Payment Card")
    }

    func test_displayName_email() {
        XCTAssertEqual(DataHandlingCategory.email.displayName, "Email Address")
    }

    // MARK: - isFinancialData

    func test_paymentCard_isFinancialData() {
        XCTAssertTrue(DataHandlingCategory.paymentCard.isFinancialData)
    }

    func test_otherCategories_areNotFinancialData() {
        let nonFinancial = DataHandlingCategory.allCases.filter { $0 != .paymentCard }
        for category in nonFinancial {
            XCTAssertFalse(
                category.isFinancialData,
                "\(category) should not be financial data"
            )
        }
    }

    // MARK: - requiresExplicitConsent

    func test_piiCategories_requireExplicitConsent() {
        let expected: Set<DataHandlingCategory> = [.email, .phone, .name, .address, .paymentCard]
        for category in expected {
            XCTAssertTrue(
                category.requiresExplicitConsent,
                "\(category) should require explicit consent"
            )
        }
    }

    func test_lowRiskCategories_doNotRequireExplicitConsent() {
        XCTAssertFalse(DataHandlingCategory.deviceID.requiresExplicitConsent)
        XCTAssertFalse(DataHandlingCategory.locationCoarse.requiresExplicitConsent)
    }

    // MARK: - CaseIterable

    func test_allCases_count() {
        XCTAssertEqual(DataHandlingCategory.allCases.count, 7,
                       "Update this test if a new DataHandlingCategory case is added")
    }

    // MARK: - Codable round-trip

    func test_codable_roundTrip() throws {
        for category in DataHandlingCategory.allCases {
            let data    = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(DataHandlingCategory.self, from: data)
            XCTAssertEqual(decoded, category, "\(category) must survive Codable round-trip")
        }
    }

    // MARK: - Hashable / Equatable

    func test_hashable_inSet() {
        let set: Set<DataHandlingCategory> = [.email, .phone, .email]
        XCTAssertEqual(set.count, 2)
    }
}
