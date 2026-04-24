#if canImport(SwiftUI)
import XCTest
@testable import Hardware

// MARK: - HardwareKeyboardShortcutCatalogTests
//
// Tests for the keyboard shortcut catalog and HardwareShortcutDescription model.
//
// Coverage:
//   - Catalog contains exactly 3 entries (⌘T, ⌘R, ⌘P)
//   - All entries have non-empty key, modifiers, description
//   - All IDs are unique
//   - ⌘T, ⌘R, ⌘P are all present
//   - HardwareShortcutDescription Identifiable: id == modifiers+key

final class HardwareKeyboardShortcutCatalogTests: XCTestCase {

    // MARK: - Catalog completeness

    func test_catalog_containsExactlyThreeShortcuts() {
        XCTAssertEqual(HardwareKeyboardShortcutCatalog.all.count, 3)
    }

    func test_catalog_containsCommandT() {
        let hasT = HardwareKeyboardShortcutCatalog.all.contains { $0.key == "T" && $0.modifiers == "⌘" }
        XCTAssertTrue(hasT, "Catalog must contain ⌘T shortcut")
    }

    func test_catalog_containsCommandR() {
        let hasR = HardwareKeyboardShortcutCatalog.all.contains { $0.key == "R" && $0.modifiers == "⌘" }
        XCTAssertTrue(hasR, "Catalog must contain ⌘R shortcut")
    }

    func test_catalog_containsCommandP() {
        let hasP = HardwareKeyboardShortcutCatalog.all.contains { $0.key == "P" && $0.modifiers == "⌘" }
        XCTAssertTrue(hasP, "Catalog must contain ⌘P shortcut")
    }

    // MARK: - Entry validation

    func test_allEntries_keyNonEmpty() {
        for entry in HardwareKeyboardShortcutCatalog.all {
            XCTAssertFalse(entry.key.isEmpty, "Shortcut key must not be empty")
        }
    }

    func test_allEntries_modifiersNonEmpty() {
        for entry in HardwareKeyboardShortcutCatalog.all {
            XCTAssertFalse(entry.modifiers.isEmpty, "Shortcut modifiers must not be empty")
        }
    }

    func test_allEntries_descriptionNonEmpty() {
        for entry in HardwareKeyboardShortcutCatalog.all {
            XCTAssertFalse(entry.description.isEmpty, "Shortcut description must not be empty")
        }
    }

    // MARK: - Unique IDs

    func test_allEntries_idsAreUnique() {
        let ids = HardwareKeyboardShortcutCatalog.all.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count, "All shortcut IDs must be unique")
    }

    // MARK: - HardwareShortcutDescription Identifiable

    func test_shortcutDescription_idFormat() {
        let desc = HardwareShortcutDescription(key: "T", modifiers: "⌘", description: "Test")
        XCTAssertEqual(desc.id, "⌘+T", "id must be modifiers+key")
    }

    func test_shortcutDescription_preservesKey() {
        let desc = HardwareShortcutDescription(key: "R", modifiers: "⌘", description: "Rescan")
        XCTAssertEqual(desc.key, "R")
    }

    func test_shortcutDescription_preservesModifiers() {
        let desc = HardwareShortcutDescription(key: "P", modifiers: "⌘", description: "Print")
        XCTAssertEqual(desc.modifiers, "⌘")
    }

    func test_shortcutDescription_preservesDescription() {
        let desc = HardwareShortcutDescription(key: "T", modifiers: "⌘", description: "Run test")
        XCTAssertEqual(desc.description, "Run test")
    }

    // MARK: - Descriptions are meaningful

    func test_commandT_description_mentionsTest() {
        let entry = HardwareKeyboardShortcutCatalog.all.first { $0.key == "T" }
        XCTAssertNotNil(entry)
        XCTAssertTrue(
            entry!.description.localizedCaseInsensitiveContains("test"),
            "⌘T description should mention 'test'"
        )
    }

    func test_commandR_description_mentionsRescan() {
        let entry = HardwareKeyboardShortcutCatalog.all.first { $0.key == "R" }
        XCTAssertNotNil(entry)
        XCTAssertTrue(
            entry!.description.localizedCaseInsensitiveContains("rescan") ||
            entry!.description.localizedCaseInsensitiveContains("refresh"),
            "⌘R description should mention 'rescan' or 'refresh'"
        )
    }

    func test_commandP_description_mentionsPrint() {
        let entry = HardwareKeyboardShortcutCatalog.all.first { $0.key == "P" }
        XCTAssertNotNil(entry)
        XCTAssertTrue(
            entry!.description.localizedCaseInsensitiveContains("print"),
            "⌘P description should mention 'print'"
        )
    }
}

#endif
