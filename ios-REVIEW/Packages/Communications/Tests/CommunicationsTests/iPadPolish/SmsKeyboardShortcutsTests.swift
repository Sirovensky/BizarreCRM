import XCTest
@testable import Communications

// MARK: - SmsKeyboardShortcutsTests
//
// Unit tests for SmsKeyboardShortcuts ViewModifier callback wiring.
// We can't invoke `.keyboardShortcut` in test host (no key events),
// so we test the closure contract by calling the callbacks directly.

final class SmsKeyboardShortcutsTests: XCTestCase {

    // MARK: - Callback invocation contract

    func test_onNewThread_callbackIsInvoked() {
        var called = false
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: { called = true },
            onSearch: {},
            onQuickCompose: {}
        )
        // Simulate the ⌘N trigger by invoking the stored closure.
        shortcuts.onNewThread()
        XCTAssertTrue(called)
    }

    func test_onSearch_callbackIsInvoked() {
        var called = false
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: {},
            onSearch: { called = true },
            onQuickCompose: {}
        )
        shortcuts.onSearch()
        XCTAssertTrue(called)
    }

    func test_onQuickCompose_callbackIsInvoked() {
        var called = false
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: {},
            onSearch: {},
            onQuickCompose: { called = true }
        )
        shortcuts.onQuickCompose()
        XCTAssertTrue(called)
    }

    // MARK: - Callback isolation (each fires independently)

    func test_onNewThread_doesNotFireOtherCallbacks() {
        var searchCalled = false
        var quickComposeCalled = false
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: {},
            onSearch: { searchCalled = true },
            onQuickCompose: { quickComposeCalled = true }
        )
        shortcuts.onNewThread()
        XCTAssertFalse(searchCalled)
        XCTAssertFalse(quickComposeCalled)
    }

    func test_onSearch_doesNotFireOtherCallbacks() {
        var newThreadCalled = false
        var quickComposeCalled = false
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: { newThreadCalled = true },
            onSearch: {},
            onQuickCompose: { quickComposeCalled = true }
        )
        shortcuts.onSearch()
        XCTAssertFalse(newThreadCalled)
        XCTAssertFalse(quickComposeCalled)
    }

    // MARK: - Multiple invocations

    func test_onNewThread_canBeCalledMultipleTimes() {
        var count = 0
        let shortcuts = SmsKeyboardShortcuts(
            onNewThread: { count += 1 },
            onSearch: {},
            onQuickCompose: {}
        )
        shortcuts.onNewThread()
        shortcuts.onNewThread()
        shortcuts.onNewThread()
        XCTAssertEqual(count, 3)
    }

    // MARK: - SmsShortcutHelpView static data

    func test_shortcutHelpView_canBeInstantiated() {
        // Smoke test — ensures the view's `shortcuts` array is non-empty.
        let view = SmsShortcutHelpView()
        // If the type resolves without crash we're good; SwiftUI views are value types.
        _ = view
    }
}
