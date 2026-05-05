import XCTest
@testable import Employees

// §22 iPad — EmployeeKeyboardShortcuts unit tests.
//
// All tests are headless. They exercise `EmployeeShortcut` metadata only,
// which is pure Swift (no UIKit guard). The `modifiers` property is
// UIKit-only and tested indirectly via the accessibility hint string.

final class EmployeeKeyboardShortcutsTests: XCTestCase {

    // MARK: - All cases present

    func test_allCases_hasFourShortcuts() {
        XCTAssertEqual(EmployeeShortcut.allCases.count, 4)
    }

    func test_allCases_containsSearch() {
        XCTAssertTrue(EmployeeShortcut.allCases.contains(.search))
    }

    func test_allCases_containsRefresh() {
        XCTAssertTrue(EmployeeShortcut.allCases.contains(.refresh))
    }

    func test_allCases_containsClockInOut() {
        XCTAssertTrue(EmployeeShortcut.allCases.contains(.clockInOut))
    }

    func test_allCases_containsDeactivate() {
        XCTAssertTrue(EmployeeShortcut.allCases.contains(.deactivate))
    }

    // MARK: - Key assignments

    func test_search_key_isF() {
        XCTAssertEqual(EmployeeShortcut.search.key, Character("f"))
    }

    func test_refresh_key_isR() {
        XCTAssertEqual(EmployeeShortcut.refresh.key, Character("r"))
    }

    func test_clockInOut_key_isI() {
        XCTAssertEqual(EmployeeShortcut.clockInOut.key, Character("i"))
    }

    func test_deactivate_key_isD() {
        XCTAssertEqual(EmployeeShortcut.deactivate.key, Character("d"))
    }

    // MARK: - Keys are distinct

    func test_allKeys_areUnique() {
        let keys = EmployeeShortcut.allCases.map { $0.key }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count,
                       "Duplicate shortcut keys detected: \(keys)")
    }

    // MARK: - Display titles non-empty

    func test_allDisplayTitles_areNonEmpty() {
        for shortcut in EmployeeShortcut.allCases {
            XCTAssertFalse(
                shortcut.displayTitle.isEmpty,
                "displayTitle is empty for \(shortcut)"
            )
        }
    }

    // MARK: - Accessibility hints reference the key character

    func test_search_accessibilityHint_containsF() {
        XCTAssertTrue(
            EmployeeShortcut.search.accessibilityHint.lowercased().contains("f")
        )
    }

    func test_refresh_accessibilityHint_containsR() {
        XCTAssertTrue(
            EmployeeShortcut.refresh.accessibilityHint.lowercased().contains("r")
        )
    }

    func test_clockInOut_accessibilityHint_containsI() {
        XCTAssertTrue(
            EmployeeShortcut.clockInOut.accessibilityHint.lowercased().contains("i")
        )
    }

    func test_deactivate_accessibilityHint_containsD() {
        XCTAssertTrue(
            EmployeeShortcut.deactivate.accessibilityHint.lowercased().contains("d")
        )
    }

    // MARK: - All hints mention "Command"

    func test_allShortcuts_hintMentionsCommand() {
        for shortcut in EmployeeShortcut.allCases {
            XCTAssertTrue(
                shortcut.accessibilityHint.contains("Command"),
                "Shortcut \(shortcut) hint does not mention 'Command': \(shortcut.accessibilityHint)"
            )
        }
    }
}
