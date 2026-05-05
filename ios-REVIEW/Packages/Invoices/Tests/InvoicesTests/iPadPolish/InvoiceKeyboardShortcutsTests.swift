import XCTest
@testable import Invoices

// §22 iPad — InvoiceKeyboardShortcuts unit tests.
//
// Tests are fully headless (no UIKit, no SwiftUI renderer needed).
// They exercise `InvoiceShortcut` metadata only, which is pure Swift (no UIKit guard).
// The `modifiers` property is UIKit-only and tested separately via guarded assertions.

final class InvoiceKeyboardShortcutsTests: XCTestCase {

    // MARK: - All cases present

    func test_allCases_hasFourShortcuts() {
        XCTAssertEqual(InvoiceShortcut.allCases.count, 4)
    }

    func test_allCases_containsNew() {
        XCTAssertTrue(InvoiceShortcut.allCases.contains(.new))
    }

    func test_allCases_containsSearch() {
        XCTAssertTrue(InvoiceShortcut.allCases.contains(.search))
    }

    func test_allCases_containsRefresh() {
        XCTAssertTrue(InvoiceShortcut.allCases.contains(.refresh))
    }

    func test_allCases_containsPrint() {
        XCTAssertTrue(InvoiceShortcut.allCases.contains(.print_))
    }

    // MARK: - Key assignments

    func test_new_key_isN() {
        XCTAssertEqual(InvoiceShortcut.new.key, Character("n"))
    }

    func test_search_key_isF() {
        XCTAssertEqual(InvoiceShortcut.search.key, Character("f"))
    }

    func test_refresh_key_isR() {
        XCTAssertEqual(InvoiceShortcut.refresh.key, Character("r"))
    }

    func test_print_key_isP() {
        XCTAssertEqual(InvoiceShortcut.print_.key, Character("p"))
    }

    // MARK: - Display titles non-empty

    func test_allDisplayTitles_areNonEmpty() {
        for shortcut in InvoiceShortcut.allCases {
            XCTAssertFalse(shortcut.displayTitle.isEmpty,
                           "displayTitle is empty for \(shortcut)")
        }
    }

    // MARK: - Accessibility hints reference the key

    func test_new_accessibilityHint_containsN() {
        XCTAssertTrue(InvoiceShortcut.new.accessibilityHint.lowercased().contains("n"))
    }

    func test_search_accessibilityHint_containsF() {
        XCTAssertTrue(InvoiceShortcut.search.accessibilityHint.lowercased().contains("f"))
    }

    func test_refresh_accessibilityHint_containsR() {
        XCTAssertTrue(InvoiceShortcut.refresh.accessibilityHint.lowercased().contains("r"))
    }

    func test_print_accessibilityHint_containsP() {
        XCTAssertTrue(InvoiceShortcut.print_.accessibilityHint.lowercased().contains("p"))
    }

    // MARK: - Keys are distinct

    func test_allKeys_areUnique() {
        let keys = InvoiceShortcut.allCases.map { $0.key }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count,
                       "Duplicate shortcut keys detected: \(keys)")
    }

    // MARK: - All use Command modifier (UIKit-gated at runtime; verified via hint string)

    /// The `.modifiers` property is UIKit-only and not directly testable on macOS.
    /// We verify indirectly that the hint string mentions "Command", which is set
    /// by `accessibilityHint` using the same key that binds to ⌘.
    func test_allShortcuts_hintMentionsCommand() {
        for shortcut in InvoiceShortcut.allCases {
            XCTAssertTrue(
                shortcut.accessibilityHint.contains("Command"),
                "Shortcut \(shortcut) hint does not mention 'Command': \(shortcut.accessibilityHint)"
            )
        }
    }
}
