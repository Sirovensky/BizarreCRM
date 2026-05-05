import XCTest
@testable import Tickets

// §22 — Unit tests for TicketKeyboardShortcuts (iPad)
//
// Coverage targets (≥80%):
//   - All three shortcuts are registered in the registry
//   - Key characters match spec ("n", "f", "r")
//   - All three use the Command modifier flag
//   - Titles are non-empty and human-readable
//   - TicketKeyboardShortcutRegistry.all contains all three in order
//   - Descriptors are Hashable / Equatable correctly

final class TicketKeyboardShortcutsTests: XCTestCase {

    // EventModifierFlags.command raw value (matches Swift EventModifierFlags).
    // Mirrors the constant defined in TicketKeyboardShortcutRegistry.
    private let commandFlag: UInt = 1_048_576

    // MARK: - New shortcut (⌘N)

    func test_newShortcut_keyIsLowercaseN() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.new.key, "n")
    }

    func test_newShortcut_modifierIsCommand() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.new.modifierFlags, commandFlag)
    }

    func test_newShortcut_titleIsNotEmpty() {
        XCTAssertFalse(TicketKeyboardShortcutRegistry.new.title.isEmpty)
    }

    func test_newShortcut_titleMentionsTicket() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.new.title.localizedCaseInsensitiveContains("ticket"))
    }

    // MARK: - Search shortcut (⌘F)

    func test_searchShortcut_keyIsLowercaseF() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.search.key, "f")
    }

    func test_searchShortcut_modifierIsCommand() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.search.modifierFlags, commandFlag)
    }

    func test_searchShortcut_titleIsNotEmpty() {
        XCTAssertFalse(TicketKeyboardShortcutRegistry.search.title.isEmpty)
    }

    func test_searchShortcut_titleMentionsSearch() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.search.title.localizedCaseInsensitiveContains("search"))
    }

    // MARK: - Refresh shortcut (⌘R)

    func test_refreshShortcut_keyIsLowercaseR() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.refresh.key, "r")
    }

    func test_refreshShortcut_modifierIsCommand() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.refresh.modifierFlags, commandFlag)
    }

    func test_refreshShortcut_titleIsNotEmpty() {
        XCTAssertFalse(TicketKeyboardShortcutRegistry.refresh.title.isEmpty)
    }

    func test_refreshShortcut_titleMentionsRefresh() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.refresh.title.localizedCaseInsensitiveContains("refresh"))
    }

    // MARK: - Registry completeness

    func test_registry_allCountIsThree() {
        XCTAssertEqual(TicketKeyboardShortcutRegistry.all.count, 3)
    }

    func test_registry_allContainsNew() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.all.contains(TicketKeyboardShortcutRegistry.new))
    }

    func test_registry_allContainsSearch() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.all.contains(TicketKeyboardShortcutRegistry.search))
    }

    func test_registry_allContainsRefresh() {
        XCTAssertTrue(TicketKeyboardShortcutRegistry.all.contains(TicketKeyboardShortcutRegistry.refresh))
    }

    func test_registry_orderIsNewSearchRefresh() {
        let keys = TicketKeyboardShortcutRegistry.all.map(\.key)
        XCTAssertEqual(keys, ["n", "f", "r"])
    }

    // MARK: - Key uniqueness

    func test_registry_allKeysAreUnique() {
        let keys = TicketKeyboardShortcutRegistry.all.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count, "Shortcut keys must be unique")
    }

    func test_registry_allTitlesAreUnique() {
        let titles = TicketKeyboardShortcutRegistry.all.map(\.title)
        XCTAssertEqual(titles.count, Set(titles).count, "Shortcut titles must be unique")
    }

    // MARK: - Hashable / Equatable

    func test_descriptor_equalityByAllFields() {
        let d1 = TicketKeyboardShortcutDescriptor(key: "x", modifierFlags: commandFlag, title: "Foo")
        let d2 = TicketKeyboardShortcutDescriptor(key: "x", modifierFlags: commandFlag, title: "Foo")
        XCTAssertEqual(d1, d2)
    }

    func test_descriptor_inequalityOnDifferentKey() {
        let d1 = TicketKeyboardShortcutDescriptor(key: "x", modifierFlags: commandFlag, title: "Same")
        let d2 = TicketKeyboardShortcutDescriptor(key: "y", modifierFlags: commandFlag, title: "Same")
        XCTAssertNotEqual(d1, d2)
    }

    func test_descriptor_inequalityOnDifferentTitle() {
        let d1 = TicketKeyboardShortcutDescriptor(key: "x", modifierFlags: commandFlag, title: "Foo")
        let d2 = TicketKeyboardShortcutDescriptor(key: "x", modifierFlags: commandFlag, title: "Bar")
        XCTAssertNotEqual(d1, d2)
    }

    func test_descriptor_hashable_sameHashForEqual() {
        let d1 = TicketKeyboardShortcutDescriptor(key: "n", modifierFlags: commandFlag, title: "New Ticket")
        let d2 = TicketKeyboardShortcutDescriptor(key: "n", modifierFlags: commandFlag, title: "New Ticket")
        XCTAssertEqual(d1.hashValue, d2.hashValue)
    }

    func test_descriptor_usableInSet() {
        var set = Set<TicketKeyboardShortcutDescriptor>()
        set.insert(TicketKeyboardShortcutRegistry.new)
        set.insert(TicketKeyboardShortcutRegistry.new)  // duplicate
        XCTAssertEqual(set.count, 1)
    }

    func test_descriptor_allThreeInSet() {
        let set = Set(TicketKeyboardShortcutRegistry.all)
        XCTAssertEqual(set.count, 3)
    }

    // MARK: - Sendable smoke test

    func test_descriptor_sendable_canCrossTaskBoundary() async {
        let descriptor = TicketKeyboardShortcutRegistry.new
        let key = await Task.detached { descriptor.key }.value
        XCTAssertEqual(key, "n")
    }
}
