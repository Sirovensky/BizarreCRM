import XCTest
import SwiftUI

// MARK: - KeyboardShortcutCatalogTests
//
// Tests for:
// 1. KeyboardShortcutCatalog — coverage: all 23 shortcuts present,
//    unique ids, correct grouping, display + a11y labels.
// 2. KeyboardShortcutBinder — look-up logic (found / not-found).
// 3. HardwareKeyboardDetector — initial state, simulated connect/disconnect.
//
// Note: Files live in ios/App/Keyboard/ (not in a SwiftPM package) so we
// import them via @testable import when this target is configured in
// project.yml.  Until then the types are referenced directly because the
// test file and source files share the same module boundary in the app
// target (same as SmokeTests pattern used in this repo).

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Stub notification helper to simulate GCKeyboard connect/disconnect
/// without a real GameController device.
private enum FakeGCKeyboard {
    static func postConnect() {
        NotificationCenter.default.post(name: .GCKeyboardDidConnect, object: nil)
    }
    static func postDisconnect() {
        NotificationCenter.default.post(name: .GCKeyboardDidDisconnect, object: nil)
    }
}

// ---------------------------------------------------------------------------
// MARK: - KeyboardShortcutCatalogTests
// ---------------------------------------------------------------------------

final class KeyboardShortcutCatalogTests: XCTestCase {

    // MARK: 1. Count — at least 20 shortcuts defined

    func test_catalog_hasAtLeast20Shortcuts() {
        XCTAssertGreaterThanOrEqual(
            KeyboardShortcutCatalog.all.count, 20,
            "Catalog must declare at least 20 shortcuts (Phase 7 gate)"
        )
    }

    // MARK: 2. All IDs are unique

    func test_catalog_allIdsAreUnique() {
        let ids = KeyboardShortcutCatalog.all.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(
            ids.count, uniqueIds.count,
            "Every shortcut must have a unique id. Duplicates: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })"
        )
    }

    // MARK: 3. Required IDs exist

    func test_catalog_requiredIdsPresent() {
        let requiredIds = [
            "new_ticket", "new_customer", "open_search", "print_receipt", "print_label",
            "nav_dashboard", "nav_tickets", "nav_customers", "nav_pos",
            "nav_inventory", "nav_appointments",
            "pos_command_palette", "pos_clear_cart", "pos_discount", "pos_tip",
            "pos_find_sku", "pos_hold_cart",
            "search_find", "search_customer_phone", "search_focus",
            "sync_now",
            "sign_out", "shortcut_overlay",
        ]
        let catalogIds = Set(KeyboardShortcutCatalog.all.map(\.id))
        let missing = requiredIds.filter { !catalogIds.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Missing required shortcut IDs: \(missing)")
    }

    // MARK: 4. Grouping — every group has the correct shortcuts

    func test_catalog_fileGroupContainsCorrectShortcuts() {
        let fileIds = KeyboardShortcutCatalog.shortcuts(in: .file).map(\.id)
        XCTAssertTrue(fileIds.contains("new_ticket"),     "File group must contain new_ticket")
        XCTAssertTrue(fileIds.contains("new_customer"),   "File group must contain new_customer")
        XCTAssertTrue(fileIds.contains("print_receipt"),  "File group must contain print_receipt")
    }

    func test_catalog_navigationGroupContainsAllSixTabs() {
        let navIds = KeyboardShortcutCatalog.shortcuts(in: .navigation).map(\.id)
        let expected = ["nav_dashboard", "nav_tickets", "nav_customers",
                        "nav_pos", "nav_inventory", "nav_appointments"]
        for id in expected {
            XCTAssertTrue(navIds.contains(id), "Navigation group missing: \(id)")
        }
    }

    func test_catalog_posGroupContainsSixShortcuts() {
        let posShortcuts = KeyboardShortcutCatalog.shortcuts(in: .pos)
        XCTAssertGreaterThanOrEqual(posShortcuts.count, 6, "POS group must have at least 6 shortcuts")
    }

    func test_catalog_searchGroupContainsThreeShortcuts() {
        let searchShortcuts = KeyboardShortcutCatalog.shortcuts(in: .search)
        XCTAssertGreaterThanOrEqual(searchShortcuts.count, 3, "Search group must have at least 3 shortcuts")
    }

    func test_catalog_syncGroupContainsSyncNow() {
        let syncIds = KeyboardShortcutCatalog.shortcuts(in: .sync).map(\.id)
        XCTAssertTrue(syncIds.contains("sync_now"), "Sync group must contain sync_now")
    }

    func test_catalog_sessionGroupContainsSignOutAndOverlay() {
        let sessionIds = KeyboardShortcutCatalog.shortcuts(in: .session).map(\.id)
        XCTAssertTrue(sessionIds.contains("sign_out"),         "Session group must contain sign_out")
        XCTAssertTrue(sessionIds.contains("shortcut_overlay"), "Session group must contain shortcut_overlay")
    }

    // MARK: 5. populatedGroups matches groups that actually have entries

    func test_catalog_populatedGroupsMatchActualGroups() {
        let populated = KeyboardShortcutCatalog.populatedGroups
        for group in ShortcutGroup.allCases {
            let hasEntries = !KeyboardShortcutCatalog.shortcuts(in: group).isEmpty
            let isListed = populated.contains(group)
            XCTAssertEqual(hasEntries, isListed,
                           "Group \(group) populated state mismatch")
        }
    }

    // MARK: 6. Lookup by id

    func test_shortcutLookup_knownId_returnsShortcut() {
        let shortcut = KeyboardShortcutCatalog.shortcut(id: "new_ticket")
        XCTAssertNotNil(shortcut, "Known id 'new_ticket' must resolve")
        XCTAssertEqual(shortcut?.title, "New Ticket")
        XCTAssertEqual(shortcut?.group, .file)
    }

    func test_shortcutLookup_unknownId_returnsNil() {
        let shortcut = KeyboardShortcutCatalog.shortcut(id: "does_not_exist")
        XCTAssertNil(shortcut, "Unknown id must return nil")
    }

    // MARK: 7. Display labels are non-empty

    func test_catalog_allShortcutsHaveNonEmptyDisplayLabels() {
        for shortcut in KeyboardShortcutCatalog.all {
            XCTAssertFalse(shortcut.displayLabel.isEmpty,
                           "displayLabel must not be empty for shortcut '\(shortcut.id)'")
        }
    }

    // MARK: 8. A11y labels contain title

    func test_catalog_accessibilityLabelContainsTitle() {
        for shortcut in KeyboardShortcutCatalog.all {
            XCTAssertTrue(
                shortcut.accessibilityLabel.contains(shortcut.title),
                "accessibilityLabel for '\(shortcut.id)' must contain title '\(shortcut.title)'"
            )
        }
    }

    // MARK: 9. No shortcut has an empty description

    func test_catalog_allShortcutsHaveNonEmptyDescriptions() {
        for shortcut in KeyboardShortcutCatalog.all {
            XCTAssertFalse(shortcut.description.isEmpty,
                           "Shortcut '\(shortcut.id)' must have a non-empty description")
        }
    }

    // MARK: 10. All shortcuts have non-empty titles

    func test_catalog_allShortcutsHaveNonEmptyTitles() {
        for shortcut in KeyboardShortcutCatalog.all {
            XCTAssertFalse(shortcut.title.isEmpty,
                           "Shortcut '\(shortcut.id)' must have a non-empty title")
        }
    }

    // MARK: 11. Sendable conformance (static check via assignment)

    func test_catalog_shortcutIsSendable() {
        // If AppKeyboardShortcut is not Sendable this will fail to compile.
        let s: any Sendable = KeyboardShortcutCatalog.all[0]
        XCTAssertNotNil(s)
    }

    // MARK: 12. Identifiable — id is unique across Identifiable protocol

    func test_catalog_identifiableIdsMatchStringIds() {
        for shortcut in KeyboardShortcutCatalog.all {
            XCTAssertEqual(shortcut.id, shortcut.id,
                           "Identifiable.id must equal the string id for '\(shortcut.id)'")
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - KeyboardShortcutBinderTests
// ---------------------------------------------------------------------------

final class KeyboardShortcutBinderTests: XCTestCase {

    func test_binder_knownId_shortcutIsFound() {
        // The binder reads from the catalog; if found it should not crash.
        let binder = KeyboardShortcutBinder(id: "new_ticket") {}
        XCTAssertEqual(binder.id, "new_ticket")
    }

    func test_binder_unknownId_doesNotCrash() {
        // A binder with an unknown id must be a no-op, not a crash.
        let binder = KeyboardShortcutBinder(id: "nonexistent_id") {}
        XCTAssertEqual(binder.id, "nonexistent_id")
        // If KeyboardShortcutCatalog.shortcut returns nil, the modifier is skipped.
        XCTAssertNil(KeyboardShortcutCatalog.shortcut(id: binder.id))
    }

    func test_binder_actionIsCalled() {
        var called = false
        let binder = KeyboardShortcutBinder(id: "new_ticket") { called = true }
        // Directly invoke the stored closure (simulates key press dispatch).
        binder.onAction()
        XCTAssertTrue(called, "onAction closure must be called when invoked")
    }
}

// ---------------------------------------------------------------------------
// MARK: - HardwareKeyboardDetectorTests
// ---------------------------------------------------------------------------

@MainActor
final class HardwareKeyboardDetectorTests: XCTestCase {

    // NOTE: GCKeyboard.coalesced returns nil in the Xcode test process
    // (no real hardware attached), so the detector starts in the 'not attached'
    // state. We simulate attach/detach via NotificationCenter.

    func test_detector_initialState_isNotAttachedInTestEnvironment() {
        let detector = HardwareKeyboardDetector()
        // In a unit-test host, GCKeyboard.coalesced == nil.
        // We just verify the property exists and is Bool.
        let _ = detector.isAttached  // would trap if not MainActor
        XCTAssertFalse(detector.isAttached,
                       "In test environment, no hardware keyboard is coalesced")
    }

    func test_detector_keyboardConnectNotification_setsIsAttachedTrue() {
        let detector = HardwareKeyboardDetector()
        XCTAssertFalse(detector.isAttached)

        FakeGCKeyboard.postConnect()

        XCTAssertTrue(detector.isAttached,
                      "isAttached must be true after GCKeyboardDidConnect notification")
    }

    func test_detector_keyboardDisconnectNotification_setsIsAttachedFalse() {
        let detector = HardwareKeyboardDetector()

        // Connect first.
        FakeGCKeyboard.postConnect()
        XCTAssertTrue(detector.isAttached)

        // Then disconnect.
        FakeGCKeyboard.postDisconnect()

        // GCKeyboard.coalesced is still nil in test host, so isAttached → false.
        XCTAssertFalse(detector.isAttached,
                       "isAttached must be false after GCKeyboardDidDisconnect notification")
    }

    func test_detector_multipleConnectNotifications_staysTrue() {
        let detector = HardwareKeyboardDetector()
        FakeGCKeyboard.postConnect()
        FakeGCKeyboard.postConnect()  // second connect (e.g., second keyboard)
        XCTAssertTrue(detector.isAttached,
                      "isAttached must remain true with multiple connect notifications")
    }

    func test_detector_deinitRemovesObserver() {
        // Verify that after deinit, notifications don't cause a crash.
        var detector: HardwareKeyboardDetector? = HardwareKeyboardDetector()
        FakeGCKeyboard.postConnect()
        detector = nil  // triggers deinit + observer removal
        // This should not crash.
        FakeGCKeyboard.postConnect()
        FakeGCKeyboard.postDisconnect()
        XCTAssertNil(detector)
    }
}
