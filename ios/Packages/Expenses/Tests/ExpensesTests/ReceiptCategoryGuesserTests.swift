import XCTest
@testable import Expenses

final class ReceiptCategoryGuesserTests: XCTestCase {

    // MARK: - Fuel

    func test_shell_isFuel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Shell"), .fuel)
    }

    func test_chevron_isFuel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Chevron Gas"), .fuel)
    }

    func test_exxon_isFuel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Exxon Mobil"), .fuel)
    }

    func test_bp_isFuel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "BP Station"), .fuel)
    }

    // MARK: - Meals

    func test_starbucks_isMeals() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Starbucks"), .meals)
    }

    func test_mcdonalds_isMeals() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "McDonald's"), .meals)
    }

    func test_chipotle_isMeals() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Chipotle Mexican Grill"), .meals)
    }

    func test_restaurantKeyword_isMeals() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Joe's Restaurant"), .meals)
    }

    func test_coffeeKeyword_isMeals() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Downtown Coffee"), .meals)
    }

    // MARK: - Supplies (hardware/general)

    func test_homeDepot_isSupplies() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Home Depot"), .supplies)
    }

    func test_amazon_isSupplies() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Amazon"), .supplies)
    }

    func test_walmart_isSupplies() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Walmart"), .supplies)
    }

    func test_lowes_isSupplies() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Lowe's Home Improvement"), .supplies)
    }

    // MARK: - Travel

    func test_delta_isTravel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Delta Airlines"), .travel)
    }

    func test_marriott_isTravel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Marriott Hotel"), .travel)
    }

    func test_uber_isTravel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Uber"), .travel)
    }

    func test_hertz_isTravel() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Hertz Car Rental"), .travel)
    }

    // MARK: - Software

    func test_adobe_isSoftware() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Adobe Creative Cloud"), .software)
    }

    func test_github_isSoftware() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "GitHub"), .software)
    }

    func test_slack_isSoftware() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Slack Technologies"), .software)
    }

    // MARK: - Shipping

    func test_fedex_isShipping() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "FedEx"), .shipping)
    }

    func test_ups_isShipping() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "UPS Store"), .shipping)
    }

    func test_usps_isShipping() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "USPS"), .shipping)
    }

    // MARK: - Office

    func test_staples_isOffice() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Staples"), .office)
    }

    func test_officeDepot_isOffice() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Office Depot"), .office)
    }

    // MARK: - Maintenance

    func test_jiffyLube_isMaintenance() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Jiffy Lube"), .maintenance)
    }

    func test_autoZone_isMaintenance() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "AutoZone"), .maintenance)
    }

    // MARK: - Insurance

    func test_geico_isInsurance() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "GEICO"), .insurance)
    }

    // MARK: - Utilities

    func test_verizon_isUtilities() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Verizon Wireless"), .utilities)
    }

    func test_comcast_isUtilities() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Comcast Xfinity"), .utilities)
    }

    // MARK: - Marketing

    func test_googleAds_isMarketing() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "Google Ads"), .marketing)
    }

    // MARK: - Case insensitivity

    func test_caseInsensitive_shell() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "SHELL FUEL"), .fuel)
    }

    func test_caseInsensitive_amazon() {
        XCTAssertEqual(ReceiptCategoryGuesser.guess(merchantName: "AMAZON"), .supplies)
    }

    // MARK: - Unknown merchant

    func test_unknownMerchant_returnsNil() {
        XCTAssertNil(ReceiptCategoryGuesser.guess(merchantName: "Zqxyvw Bizarro Corp"))
    }

    // MARK: - categoryString

    func test_categoryString_knownMerchant() {
        XCTAssertEqual(ReceiptCategoryGuesser.categoryString(for: "Shell"), "Fuel")
    }

    func test_categoryString_unknownMerchant_returnsOther() {
        XCTAssertEqual(ReceiptCategoryGuesser.categoryString(for: "Xyzzy Unknown"), "Other")
    }

    // MARK: - All categories reachable

    func test_allCategoriesHaveAtLeastOneRule() {
        // Spot-check critical categories are reachable
        let testCases: [(merchant: String, expected: ReceiptCategoryGuesser.Category)] = [
            ("Shell", .fuel),
            ("Starbucks", .meals),
            ("Home Depot", .supplies),
            ("Delta Airlines", .travel),
            ("Staples", .office),
            ("FedEx", .shipping),
            ("Verizon", .utilities),
            ("Adobe", .software),
            ("Google Ads", .marketing),
            ("GEICO", .insurance),
            ("Jiffy Lube", .maintenance),
        ]
        for tc in testCases {
            XCTAssertEqual(
                ReceiptCategoryGuesser.guess(merchantName: tc.merchant),
                tc.expected,
                "\(tc.merchant) should be \(tc.expected.rawValue)"
            )
        }
    }
}
