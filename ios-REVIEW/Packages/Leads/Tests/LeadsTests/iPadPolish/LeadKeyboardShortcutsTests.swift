import XCTest
@testable import Leads

// MARK: - LeadKeyboardShortcutsTests

final class LeadKeyboardShortcutsTests: XCTestCase {

    // MARK: - LeadShortcutDescriptions catalogue

    func test_shortcutCatalogue_isNonEmpty() {
        XCTAssertFalse(LeadShortcutDescriptions.all.isEmpty)
    }

    func test_shortcutCatalogue_count_isNine() {
        // 9 defined shortcuts: N, F, R, C, ⌫, A, S, ↓, ↑
        XCTAssertEqual(LeadShortcutDescriptions.all.count, 9)
    }

    func test_allEntries_haveNonEmptyTitle() {
        for entry in LeadShortcutDescriptions.all {
            XCTAssertFalse(entry.title.isEmpty, "Entry \(entry.key) has empty title")
        }
    }

    func test_allEntries_haveNonEmptyKey() {
        for entry in LeadShortcutDescriptions.all {
            XCTAssertFalse(entry.key.isEmpty, "Entry '\(entry.title)' has empty key")
        }
    }

    func test_newLeadShortcut_usesCommandN() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .newLead }
        XCTAssertNotNil(entry, "newLead shortcut not found in catalogue")
        XCTAssertEqual(entry?.key, "N")
        XCTAssertTrue(entry?.modifiers.contains("⌘") ?? false)
    }

    func test_searchShortcut_usesCommandF() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .search }
        XCTAssertNotNil(entry, "search shortcut not found")
        XCTAssertEqual(entry?.key, "F")
    }

    func test_refreshShortcut_usesCommandR() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .refresh }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.key, "R")
    }

    func test_archiveShortcut_usesCommandDelete() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .archiveSelected }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.key, "⌫")
    }

    func test_nextLeadShortcut_usesDownArrow() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .nextLead }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.key, "↓")
    }

    func test_previousLeadShortcut_usesUpArrow() {
        let entry = LeadShortcutDescriptions.all.first { $0.action == .previousLead }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.key, "↑")
    }

    // MARK: - Unique actions

    func test_allShortcutActions_areUnique() {
        let actions = LeadShortcutDescriptions.all.map { $0.action }
        let unique = Set(actions.map { "\($0)" })
        XCTAssertEqual(unique.count, actions.count, "Duplicate shortcut actions found")
    }

    // MARK: - LeadKeyboardShortcutAction modifier dispatch

    func test_shortcutModifier_dispatchesNewLead() {
        var received: LeadKeyboardShortcutAction?
        let modifier = LeadKeyboardShortcuts { received = $0 }
        modifier.onAction(.newLead)
        guard case .newLead = received else {
            XCTFail("Expected .newLead")
            return
        }
    }

    func test_shortcutModifier_dispatchesRefresh() {
        var received: LeadKeyboardShortcutAction?
        let modifier = LeadKeyboardShortcuts { received = $0 }
        modifier.onAction(.refresh)
        guard case .refresh = received else {
            XCTFail("Expected .refresh")
            return
        }
    }

    func test_shortcutModifier_dispatchesNextLead() {
        var received: LeadKeyboardShortcutAction?
        let modifier = LeadKeyboardShortcuts { received = $0 }
        modifier.onAction(.nextLead)
        guard case .nextLead = received else {
            XCTFail("Expected .nextLead")
            return
        }
    }

    func test_shortcutModifier_dispatchesPreviousLead() {
        var received: LeadKeyboardShortcutAction?
        let modifier = LeadKeyboardShortcuts { received = $0 }
        modifier.onAction(.previousLead)
        guard case .previousLead = received else {
            XCTFail("Expected .previousLead")
            return
        }
    }

    func test_shortcutModifier_dispatchesArchive() {
        var received: LeadKeyboardShortcutAction?
        let modifier = LeadKeyboardShortcuts { received = $0 }
        modifier.onAction(.archiveSelected)
        guard case .archiveSelected = received else {
            XCTFail("Expected .archiveSelected")
            return
        }
    }
}

// MARK: - LeadKeyboardShortcutAction: Equatable via string description

extension LeadKeyboardShortcutAction: Equatable {
    public static func == (lhs: LeadKeyboardShortcutAction, rhs: LeadKeyboardShortcutAction) -> Bool {
        switch (lhs, rhs) {
        case (.newLead, .newLead),
             (.search, .search),
             (.refresh, .refresh),
             (.convertSelected, .convertSelected),
             (.archiveSelected, .archiveSelected),
             (.assignSelected, .assignSelected),
             (.changeStatusSelected, .changeStatusSelected),
             (.nextLead, .nextLead),
             (.previousLead, .previousLead):
            return true
        default:
            return false
        }
    }
}
