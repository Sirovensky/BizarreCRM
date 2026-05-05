import XCTest
@testable import Voice

/// §22 — `VoiceShortcut` constant tests.
///
/// SwiftUI's `.keyboardShortcut(...)` modifier cannot be tested in a headless
/// XCTest host (no UIApplication / UIScene). These tests verify the _values_
/// of the shortcut descriptor constants so regressions in key or modifier
/// choice are caught without needing a UI host.
final class VoiceKeyboardShortcutsTests: XCTestCase {

    // MARK: - Key equivalents

    func test_searchShortcut_keyIsF() {
        XCTAssertEqual(VoiceShortcut.search, KeyEquivalent("f"),
                       "⌘F must activate search")
    }

    func test_callbackShortcut_keyIsC() {
        XCTAssertEqual(VoiceShortcut.callback, KeyEquivalent("c"),
                       "⌘C must trigger callback")
    }

    func test_playPauseShortcut_keyIsSpace() {
        XCTAssertEqual(VoiceShortcut.playPause, KeyEquivalent(" "),
                       "Space must toggle play/pause")
    }

    // MARK: - Modifiers

    func test_commandModifiers_containsCommand() {
        XCTAssertTrue(VoiceShortcut.commandModifiers.contains(.command),
                      "Search and callback use ⌘ modifier")
    }

    func test_noModifiers_isEmpty() {
        XCTAssertEqual(VoiceShortcut.noModifiers, [],
                       "Space bar requires no modifier")
    }

    // MARK: - Distinct keys

    func test_searchAndCallbackAreDifferentKeys() {
        XCTAssertNotEqual(VoiceShortcut.search, VoiceShortcut.callback,
                          "⌘F and ⌘C must not collide")
    }

    func test_playPauseIsDistinctFromSearch() {
        XCTAssertNotEqual(VoiceShortcut.playPause, VoiceShortcut.search)
    }

    func test_playPauseIsDistinctFromCallback() {
        XCTAssertNotEqual(VoiceShortcut.playPause, VoiceShortcut.callback)
    }
}
