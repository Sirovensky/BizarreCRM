import XCTest
@testable import Reports

// MARK: - ReportKeyboardShortcutsTests
//
// Tests that:
// - `allReportShortcutBindings()` returns all 6 expected shortcuts.
// - Each category shortcut maps to the correct ReportCategory.
// - ⌘E and ⌘R map to export and refresh actions, not to a category.
// - No duplicate (key, modifiers) pairs exist.
// - All keys are in the expected set.

final class ReportKeyboardShortcutsTests: XCTestCase {

    // MARK: - Count

    func test_allBindings_countIsSix() {
        XCTAssertEqual(allReportShortcutBindings().count, 6)
    }

    // MARK: - Category shortcuts

    func test_cmd1_selectsRevenue() {
        let binding = shortcut(key: "1")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.category, .revenue)
        XCTAssertEqual(binding?.action, .selectCategory)
    }

    func test_cmd2_selectsExpenses() {
        let binding = shortcut(key: "2")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.category, .expenses)
        XCTAssertEqual(binding?.action, .selectCategory)
    }

    func test_cmd3_selectsInventory() {
        let binding = shortcut(key: "3")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.category, .inventory)
        XCTAssertEqual(binding?.action, .selectCategory)
    }

    func test_cmd4_selectsOwnerPL() {
        let binding = shortcut(key: "4")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.category, .ownerPL)
        XCTAssertEqual(binding?.action, .selectCategory)
    }

    // MARK: - Export shortcut (⌘E)

    func test_cmdE_isExportAction() {
        let binding = shortcut(key: "e")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.action, .export)
        XCTAssertNil(binding?.category, "Export shortcut should not be tied to a category")
    }

    // MARK: - Refresh shortcut (⌘R)

    func test_cmdR_isRefreshAction() {
        let binding = shortcut(key: "r")
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.action, .refresh)
        XCTAssertNil(binding?.category, "Refresh shortcut should not be tied to a category")
    }

    // MARK: - All shortcuts use Command modifier

    func test_allBindings_useCommandModifier() {
        for binding in allReportShortcutBindings() {
            XCTAssertTrue(
                binding.modifiers.contains(.command),
                "Shortcut \(binding.key) should require Command modifier"
            )
        }
    }

    // MARK: - No duplicate bindings

    func test_noDuplicateKeyBindings() {
        let bindings = allReportShortcutBindings()
        let keys = bindings.map { $0.key }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(
            keys.count, uniqueKeys.count,
            "Found duplicate shortcut key bindings: \(keys)"
        )
    }

    // MARK: - Category shortcuts cover all four categories exactly once

    func test_categoryShortcuts_coverAllFourCategories() {
        let categoryBindings = allReportShortcutBindings().filter { $0.action == .selectCategory }
        XCTAssertEqual(categoryBindings.count, 4)
        let categories = Set(categoryBindings.compactMap { $0.category })
        XCTAssertEqual(categories.count, 4)
        XCTAssertTrue(categories.contains(.revenue))
        XCTAssertTrue(categories.contains(.expenses))
        XCTAssertTrue(categories.contains(.inventory))
        XCTAssertTrue(categories.contains(.ownerPL))
    }

    // MARK: - Action types

    func test_allActionTypes_presentInBindings() {
        let actions = Set(allReportShortcutBindings().map { $0.action })
        XCTAssertTrue(actions.contains(.selectCategory))
        XCTAssertTrue(actions.contains(.export))
        XCTAssertTrue(actions.contains(.refresh))
    }

    // MARK: - Helper

    private func shortcut(key: Character) -> ReportShortcutBinding? {
        allReportShortcutBindings().first { $0.key == key }
    }
}
