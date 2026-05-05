import XCTest
@testable import Appointments
import SwiftUI

// MARK: - AppointmentKeyboardShortcutsTests

final class AppointmentKeyboardShortcutsTests: XCTestCase {

    // MARK: - AppointmentKeyboardShortcutsDescriptor

    func test_descriptor_hasExactlyFourEntries() {
        XCTAssertEqual(AppointmentKeyboardShortcutsDescriptor.all.count, 4)
    }

    func test_descriptor_containsNewShortcut() {
        let entry = AppointmentKeyboardShortcutsDescriptor.all.first { $0.id == "new" }
        XCTAssertNotNil(entry, "Descriptor must contain 'new' entry")
        XCTAssertEqual(entry?.key, "N")
        XCTAssertEqual(entry?.modifiers, "⌘")
    }

    func test_descriptor_containsTodayShortcut() {
        let entry = AppointmentKeyboardShortcutsDescriptor.all.first { $0.id == "today" }
        XCTAssertNotNil(entry, "Descriptor must contain 'today' entry")
        XCTAssertEqual(entry?.key, "T")
        XCTAssertEqual(entry?.modifiers, "⌘")
    }

    func test_descriptor_containsFindShortcut() {
        let entry = AppointmentKeyboardShortcutsDescriptor.all.first { $0.id == "find" }
        XCTAssertNotNil(entry, "Descriptor must contain 'find' entry")
        XCTAssertEqual(entry?.key, "F")
        XCTAssertEqual(entry?.modifiers, "⌘")
    }

    func test_descriptor_containsRefreshShortcut() {
        let entry = AppointmentKeyboardShortcutsDescriptor.all.first { $0.id == "refresh" }
        XCTAssertNotNil(entry, "Descriptor must contain 'refresh' entry")
        XCTAssertEqual(entry?.key, "R")
        XCTAssertEqual(entry?.modifiers, "⌘")
    }

    func test_descriptor_allEntriesHaveNonEmptyLabel() {
        for entry in AppointmentKeyboardShortcutsDescriptor.all {
            XCTAssertFalse(entry.label.isEmpty, "Entry '\(entry.id)' must have a non-empty label")
        }
    }

    func test_descriptor_allEntriesHaveNonEmptySymbol() {
        for entry in AppointmentKeyboardShortcutsDescriptor.all {
            XCTAssertFalse(entry.symbol.isEmpty, "Entry '\(entry.id)' must have a non-empty system image symbol")
        }
    }

    func test_descriptor_allIDsAreUnique() {
        let ids = AppointmentKeyboardShortcutsDescriptor.all.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All shortcut IDs must be unique")
    }

    // MARK: - ShortcutEntry Identifiable

    func test_shortcutEntry_idEqualsExpectedString() {
        let entry = AppointmentKeyboardShortcutsDescriptor.ShortcutEntry(
            id: "test",
            label: "Test",
            symbol: "star",
            modifiers: "⌘",
            key: "X"
        )
        XCTAssertEqual(entry.id, "test")
    }

    // MARK: - ViewModifier callbacks

    func test_modifier_onNew_isInvokedViaCallback() {
        var called = false
        let modifier = AppointmentKeyboardShortcutsModifier(
            onNew: { called = true },
            onToday: {},
            onFind: {},
            onRefresh: {}
        )
        modifier.onNew()
        XCTAssertTrue(called)
    }

    func test_modifier_onToday_isInvokedViaCallback() {
        var called = false
        let modifier = AppointmentKeyboardShortcutsModifier(
            onNew: {},
            onToday: { called = true },
            onFind: {},
            onRefresh: {}
        )
        modifier.onToday()
        XCTAssertTrue(called)
    }

    func test_modifier_onFind_isInvokedViaCallback() {
        var called = false
        let modifier = AppointmentKeyboardShortcutsModifier(
            onNew: {},
            onToday: {},
            onFind: { called = true },
            onRefresh: {}
        )
        modifier.onFind()
        XCTAssertTrue(called)
    }

    func test_modifier_onRefresh_isInvokedViaCallback() {
        var called = false
        let modifier = AppointmentKeyboardShortcutsModifier(
            onNew: {},
            onToday: {},
            onFind: {},
            onRefresh: { called = true }
        )
        modifier.onRefresh()
        XCTAssertTrue(called)
    }

    // MARK: - Multiple callbacks can be invoked independently

    func test_modifier_callbacksAreIndependent() {
        var newCount = 0
        var refreshCount = 0
        let modifier = AppointmentKeyboardShortcutsModifier(
            onNew: { newCount += 1 },
            onToday: {},
            onFind: {},
            onRefresh: { refreshCount += 1 }
        )
        modifier.onNew()
        modifier.onNew()
        modifier.onRefresh()
        XCTAssertEqual(newCount, 2)
        XCTAssertEqual(refreshCount, 1)
    }
}
