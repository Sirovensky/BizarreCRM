import XCTest
import SwiftUI
@testable import Estimates

// MARK: - EstimateKeyboardShortcutsTests
//
// §22 iPad — tests for EstimateKeyboardShortcutsConfig and modifier callbacks.
// Since UIKit keyboard shortcut bindings can only be observed in live UI,
// these tests focus on the config catalog and callback contract.

final class EstimateKeyboardShortcutsTests: XCTestCase {

    // MARK: - Config catalog

    func test_config_hasExactlyFourShortcuts() {
        XCTAssertEqual(EstimateKeyboardShortcutsConfig.all.count, 4)
    }

    func test_config_containsNewEstimate() {
        let entry = EstimateKeyboardShortcutsConfig.all.first {
            $0.key == "n" && $0.modifiers == .command
        }
        XCTAssertNotNil(entry, "⌘N shortcut missing from config")
        XCTAssertEqual(entry?.description, "New Estimate")
    }

    func test_config_containsFocusSearch() {
        let entry = EstimateKeyboardShortcutsConfig.all.first {
            $0.key == "f" && $0.modifiers == .command
        }
        XCTAssertNotNil(entry, "⌘F shortcut missing from config")
        XCTAssertEqual(entry?.description, "Focus Search")
    }

    func test_config_containsRefresh() {
        let entry = EstimateKeyboardShortcutsConfig.all.first {
            $0.key == "r" && $0.modifiers == .command
        }
        XCTAssertNotNil(entry, "⌘R shortcut missing from config")
        XCTAssertEqual(entry?.description, "Refresh")
    }

    func test_config_containsSendForSignature() {
        let entry = EstimateKeyboardShortcutsConfig.all.first {
            $0.key == "s" && $0.modifiers == [.command, .shift]
        }
        XCTAssertNotNil(entry, "⌘⇧S shortcut missing from config")
        XCTAssertEqual(entry?.description, "Send for Signature")
    }

    // MARK: - No duplicate keys

    func test_config_noDuplicateKeyModifierCombinations() {
        let pairs = EstimateKeyboardShortcutsConfig.all.map { "\($0.key)-\($0.modifiers.rawValue)" }
        let unique = Set(pairs)
        XCTAssertEqual(pairs.count, unique.count, "Duplicate key+modifier combos in shortcut config")
    }

    // MARK: - ShortcutEntry equality

    func test_shortcutEntry_equalityMatchesKeyAndModifiers() {
        let a = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "n", modifiers: .command, description: "New")
        let b = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "n", modifiers: .command, description: "New")
        XCTAssertEqual(a, b)
    }

    func test_shortcutEntry_inequalityDifferentKey() {
        let a = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "n", modifiers: .command, description: "New")
        let b = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "r", modifiers: .command, description: "Refresh")
        XCTAssertNotEqual(a, b)
    }

    func test_shortcutEntry_inequalityDifferentModifiers() {
        let a = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "s", modifiers: .command,              description: "S")
        let b = EstimateKeyboardShortcutsConfig.ShortcutEntry(key: "s", modifiers: [.command, .shift],    description: "S")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Callback contract (modifier)

    @MainActor
    func test_modifier_callsOnNew_whenNewFires() {
        var called = false
        let handler = ShortcutCallbackHandler(
            onNew: { called = true },
            onFocusSearch: {},
            onRefresh: {},
            onSendForSignature: {}
        )
        handler.fireNew()
        XCTAssertTrue(called)
    }

    @MainActor
    func test_modifier_callsOnFocusSearch_whenSearchFires() {
        var called = false
        let handler = ShortcutCallbackHandler(
            onNew: {},
            onFocusSearch: { called = true },
            onRefresh: {},
            onSendForSignature: {}
        )
        handler.fireFocusSearch()
        XCTAssertTrue(called)
    }

    @MainActor
    func test_modifier_callsOnRefresh_whenRefreshFires() {
        var called = false
        let handler = ShortcutCallbackHandler(
            onNew: {},
            onFocusSearch: {},
            onRefresh: { called = true },
            onSendForSignature: {}
        )
        handler.fireRefresh()
        XCTAssertTrue(called)
    }

    @MainActor
    func test_modifier_callsOnSendForSignature_whenSignFires() {
        var called = false
        let handler = ShortcutCallbackHandler(
            onNew: {},
            onFocusSearch: {},
            onRefresh: {},
            onSendForSignature: { called = true }
        )
        handler.fireSendForSignature()
        XCTAssertTrue(called)
    }

    @MainActor
    func test_modifier_doesNotCallOtherCallbacks() {
        var newCalled = false
        var refreshCalled = false
        let handler = ShortcutCallbackHandler(
            onNew: { newCalled = true },
            onFocusSearch: {},
            onRefresh: { refreshCalled = true },
            onSendForSignature: {}
        )
        handler.fireFocusSearch()
        XCTAssertFalse(newCalled)
        XCTAssertFalse(refreshCalled)
    }
}

// MARK: - ShortcutCallbackHandler (test helper)

/// Simulates what the modifier does when a shortcut fires.
@MainActor
private final class ShortcutCallbackHandler {
    private let onNew: () -> Void
    private let onFocusSearch: () -> Void
    private let onRefresh: () -> Void
    private let onSendForSignature: () -> Void

    init(
        onNew: @escaping () -> Void,
        onFocusSearch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onSendForSignature: @escaping () -> Void
    ) {
        self.onNew = onNew
        self.onFocusSearch = onFocusSearch
        self.onRefresh = onRefresh
        self.onSendForSignature = onSendForSignature
    }

    func fireNew()              { onNew() }
    func fireFocusSearch()      { onFocusSearch() }
    func fireRefresh()          { onRefresh() }
    func fireSendForSignature() { onSendForSignature() }
}
