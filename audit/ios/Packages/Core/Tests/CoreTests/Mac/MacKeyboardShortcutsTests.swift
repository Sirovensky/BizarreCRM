// CoreTests/Mac/MacKeyboardShortcutsTests.swift
//
// Unit tests for §23 MacKeyboardShortcuts catalog.
//
// Coverage:
//   - All 9 shortcuts exist with non-empty id, description
//   - Modifier combinations are correct (⌘, ⌘⇧)
//   - Key characters are the documented values
//   - All IDs are unique (no accidental duplicates)
//   - `all` list is exhaustive
//   - `MacShortcut.keyboardShortcut` interop compiles
//   - Immutability: MacShortcut is a value type — copies are independent
//
// §23 Mac polish — keyboard shortcut tests

import XCTest
import SwiftUI
@testable import Core

final class MacKeyboardShortcutsTests: XCTestCase {

    // MARK: - Non-empty strings

    func test_allShortcuts_idNonEmpty() {
        for shortcut in MacKeyboardShortcuts.all {
            XCTAssertFalse(shortcut.id.isEmpty, "id must not be empty for \(shortcut.description)")
        }
    }

    func test_allShortcuts_descriptionNonEmpty() {
        for shortcut in MacKeyboardShortcuts.all {
            XCTAssertFalse(shortcut.description.isEmpty, "description must not be empty for id=\(shortcut.id)")
        }
    }

    // MARK: - Catalog completeness (9 shortcuts)

    func test_allShortcuts_count() {
        XCTAssertEqual(MacKeyboardShortcuts.all.count, 9, "Catalog must contain exactly 9 shortcuts")
    }

    func test_allShortcuts_uniqueIDs() {
        let ids = MacKeyboardShortcuts.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All shortcut IDs must be unique")
    }

    // MARK: - Individual shortcuts — keys

    func test_quit_key() {
        XCTAssertEqual(MacKeyboardShortcuts.quit.key, "q")
    }

    func test_closeWindow_key() {
        XCTAssertEqual(MacKeyboardShortcuts.closeWindow.key, "w")
    }

    func test_newItem_key() {
        XCTAssertEqual(MacKeyboardShortcuts.newItem.key, "n")
    }

    func test_find_key() {
        XCTAssertEqual(MacKeyboardShortcuts.find.key, "f")
    }

    func test_commandPalette_key() {
        XCTAssertEqual(MacKeyboardShortcuts.commandPalette.key, "k")
    }

    func test_refresh_key() {
        XCTAssertEqual(MacKeyboardShortcuts.refresh.key, "r")
    }

    func test_save_key() {
        XCTAssertEqual(MacKeyboardShortcuts.save.key, "s")
    }

    func test_undo_key() {
        XCTAssertEqual(MacKeyboardShortcuts.undo.key, "z")
    }

    func test_redo_key() {
        XCTAssertEqual(MacKeyboardShortcuts.redo.key, "z")
    }

    // MARK: - Modifiers

    func test_commandOnlyShortcuts_haveCommandModifier() {
        let commandOnly: [MacShortcut] = [
            MacKeyboardShortcuts.quit,
            MacKeyboardShortcuts.closeWindow,
            MacKeyboardShortcuts.newItem,
            MacKeyboardShortcuts.find,
            MacKeyboardShortcuts.commandPalette,
            MacKeyboardShortcuts.refresh,
            MacKeyboardShortcuts.save,
            MacKeyboardShortcuts.undo,
        ]
        for shortcut in commandOnly {
            XCTAssertEqual(shortcut.modifiers, .command,
                           "Expected .command modifier for \(shortcut.id)")
        }
    }

    func test_redo_hasCommandShiftModifier() {
        XCTAssertEqual(
            MacKeyboardShortcuts.redo.modifiers,
            [.command, .shift],
            "Redo must use ⌘⇧"
        )
    }

    func test_undoAndRedo_haveDistinctModifiers() {
        XCTAssertNotEqual(
            MacKeyboardShortcuts.undo.modifiers,
            MacKeyboardShortcuts.redo.modifiers,
            "Undo and Redo share the same key but must differ in modifiers"
        )
    }

    // MARK: - Stable IDs (regression)

    func test_stableIDs() {
        XCTAssertEqual(MacKeyboardShortcuts.quit.id,           "mac.quit")
        XCTAssertEqual(MacKeyboardShortcuts.closeWindow.id,    "mac.closeWindow")
        XCTAssertEqual(MacKeyboardShortcuts.newItem.id,        "mac.newItem")
        XCTAssertEqual(MacKeyboardShortcuts.find.id,           "mac.find")
        XCTAssertEqual(MacKeyboardShortcuts.commandPalette.id, "mac.commandPalette")
        XCTAssertEqual(MacKeyboardShortcuts.refresh.id,        "mac.refresh")
        XCTAssertEqual(MacKeyboardShortcuts.save.id,           "mac.save")
        XCTAssertEqual(MacKeyboardShortcuts.undo.id,           "mac.undo")
        XCTAssertEqual(MacKeyboardShortcuts.redo.id,           "mac.redo")
    }

    // MARK: - Stable descriptions (regression)

    func test_stableDescriptions() {
        XCTAssertEqual(MacKeyboardShortcuts.quit.description,           "Quit BizarreCRM")
        XCTAssertEqual(MacKeyboardShortcuts.closeWindow.description,    "Close Window")
        XCTAssertEqual(MacKeyboardShortcuts.newItem.description,        "New Item")
        XCTAssertEqual(MacKeyboardShortcuts.find.description,           "Find")
        XCTAssertEqual(MacKeyboardShortcuts.commandPalette.description, "Open Command Palette")
        XCTAssertEqual(MacKeyboardShortcuts.refresh.description,        "Refresh")
        XCTAssertEqual(MacKeyboardShortcuts.save.description,           "Save")
        XCTAssertEqual(MacKeyboardShortcuts.undo.description,           "Undo")
        XCTAssertEqual(MacKeyboardShortcuts.redo.description,           "Redo")
    }

    // MARK: - `all` list contains each named shortcut

    func test_allList_containsQuit() {
        XCTAssertTrue(MacKeyboardShortcuts.all.contains(MacKeyboardShortcuts.quit))
    }

    func test_allList_containsNewItem() {
        XCTAssertTrue(MacKeyboardShortcuts.all.contains(MacKeyboardShortcuts.newItem))
    }

    func test_allList_containsRedo() {
        XCTAssertTrue(MacKeyboardShortcuts.all.contains(MacKeyboardShortcuts.redo))
    }

    // MARK: - SwiftUI interop (compile-time + runtime)

    func test_keyboardShortcut_compiles() {
        // Verify the computed property returns the correct type — no crash.
        let ks: KeyboardShortcut = MacKeyboardShortcuts.newItem.keyboardShortcut
        _ = ks  // consumed
    }

    func test_keyboardShortcut_key_matches() {
        let ks = MacKeyboardShortcuts.save.keyboardShortcut
        XCTAssertEqual(ks.key, "s")
    }

    func test_keyboardShortcut_modifiers_matches() {
        let ks = MacKeyboardShortcuts.redo.keyboardShortcut
        XCTAssertEqual(ks.modifiers, [.command, .shift])
    }

    // MARK: - Equatable / value semantics

    func test_equalShortcuts_areEqual() {
        let a = MacShortcut(id: "x", key: "a", modifiers: .command, description: "A")
        let b = MacShortcut(id: "x", key: "a", modifiers: .command, description: "A")
        XCTAssertEqual(a, b)
    }

    func test_shortcutsWithDifferentKeys_notEqual() {
        let a = MacShortcut(id: "x", key: "a", description: "A")
        let b = MacShortcut(id: "x", key: "b", description: "A")
        XCTAssertNotEqual(a, b)
    }

    func test_shortcutsWithDifferentModifiers_notEqual() {
        let a = MacShortcut(id: "x", key: "z", modifiers: .command,          description: "Undo")
        let b = MacShortcut(id: "x", key: "z", modifiers: [.command, .shift], description: "Undo")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Sendable (compile-time)

    func test_sendable_compilesClean() {
        let shortcut = MacKeyboardShortcuts.newItem
        let _: @Sendable () -> MacShortcut = { shortcut }
    }
}
