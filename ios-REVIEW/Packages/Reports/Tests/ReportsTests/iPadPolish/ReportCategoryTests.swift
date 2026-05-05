import XCTest
@testable import Reports

// MARK: - ReportCategoryTests
//
// Tests that ReportCategory provides correct values for all four categories
// and that helpers return non-empty/non-nil values for each case.

final class ReportCategoryTests: XCTestCase {

    // MARK: - allCases coverage

    func test_allCases_countIsFour() {
        XCTAssertEqual(ReportCategory.allCases.count, 4)
    }

    func test_allCases_containsExpectedCategories() {
        let cases = ReportCategory.allCases
        XCTAssertTrue(cases.contains(.revenue))
        XCTAssertTrue(cases.contains(.expenses))
        XCTAssertTrue(cases.contains(.inventory))
        XCTAssertTrue(cases.contains(.ownerPL))
    }

    // MARK: - displayName

    func test_displayName_revenue() {
        XCTAssertEqual(ReportCategory.revenue.displayName, "Revenue")
    }

    func test_displayName_expenses() {
        XCTAssertEqual(ReportCategory.expenses.displayName, "Expenses")
    }

    func test_displayName_inventory() {
        XCTAssertEqual(ReportCategory.inventory.displayName, "Inventory")
    }

    func test_displayName_ownerPL() {
        XCTAssertEqual(ReportCategory.ownerPL.displayName, "Owner P&L")
    }

    // MARK: - rawValue (used as Identifiable id)

    func test_id_equalsRawValue() {
        for category in ReportCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    // MARK: - systemImage

    func test_systemImage_isNonEmpty_forAllCases() {
        for category in ReportCategory.allCases {
            XCTAssertFalse(
                category.systemImage.isEmpty,
                "\(category.displayName) should have a non-empty systemImage"
            )
        }
    }

    func test_systemImage_revenue_containsArrowUp() {
        XCTAssertTrue(ReportCategory.revenue.systemImage.contains("arrow.up"))
    }

    func test_systemImage_expenses_containsArrowDown() {
        XCTAssertTrue(ReportCategory.expenses.systemImage.contains("arrow.down"))
    }

    func test_systemImage_inventory_containsBox() {
        XCTAssertTrue(ReportCategory.inventory.systemImage.contains("shippingbox"))
    }

    func test_systemImage_ownerPL_containsChart() {
        XCTAssertTrue(ReportCategory.ownerPL.systemImage.contains("chart"))
    }

    // MARK: - accentColor (non-nil, distinct per category)

    func test_accentColors_areDistinctAcrossCategories() {
        // Each category has its own accent — verify they don't all resolve to the same string
        let descriptions = ReportCategory.allCases.map { "\($0.accentColor)" }
        let unique = Set(descriptions)
        // At least 2 distinct colors across 4 categories
        XCTAssertGreaterThan(unique.count, 1)
    }
}
