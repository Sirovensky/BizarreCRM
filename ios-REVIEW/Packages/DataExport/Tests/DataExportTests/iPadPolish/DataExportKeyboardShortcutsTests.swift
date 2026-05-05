import Testing
import SwiftUI
import Foundation
@testable import DataExport

// MARK: - DataExportKeyboardShortcutsTests

@Suite("DataExportKeyboardShortcuts — shortcut definitions")
struct DataExportKeyboardShortcutsTests {

    // MARK: - Completeness

    @Test("all shortcuts array contains 9 entries")
    func allShortcutsCount() {
        #expect(DataExportKeyboardShortcuts.all.count == 9)
    }

    @Test("all shortcuts have unique IDs")
    func allShortcutsUniqueIDs() {
        let ids = DataExportKeyboardShortcuts.all.map(\.id)
        let uniqueIds = Set(ids)
        #expect(uniqueIds.count == ids.count)
    }

    @Test("all shortcuts have non-empty displayTitle")
    func allShortcutsHaveDisplayTitle() {
        for shortcut in DataExportKeyboardShortcuts.all {
            #expect(!shortcut.displayTitle.isEmpty, "Shortcut \(shortcut.id) has empty displayTitle")
        }
    }

    @Test("all shortcuts have non-empty accessibilityHint")
    func allShortcutsHaveAccessibilityHint() {
        for shortcut in DataExportKeyboardShortcuts.all {
            #expect(!shortcut.accessibilityHint.isEmpty, "Shortcut \(shortcut.id) has empty accessibilityHint")
        }
    }

    // MARK: - Individual shortcut definitions

    @Test("newExport shortcut uses ⌘N")
    func newExportShortcut() {
        let s = DataExportKeyboardShortcuts.newExport
        #expect(s.key == "n")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.new")
    }

    @Test("downloadSelected shortcut uses ⌘D")
    func downloadSelectedShortcut() {
        let s = DataExportKeyboardShortcuts.downloadSelected
        #expect(s.key == "d")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.download")
    }

    @Test("shareSelected shortcut uses ⌘⇧S")
    func shareSelectedShortcut() {
        let s = DataExportKeyboardShortcuts.shareSelected
        #expect(s.key == "s")
        #expect(s.modifiers.contains(.command))
        #expect(s.modifiers.contains(.shift))
        #expect(s.id == "export.share")
    }

    @Test("refresh shortcut uses ⌘R")
    func refreshShortcut() {
        let s = DataExportKeyboardShortcuts.refresh
        #expect(s.key == "r")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.refresh")
    }

    @Test("cancelSelected shortcut uses ⌘⌫")
    func cancelSelectedShortcut() {
        let s = DataExportKeyboardShortcuts.cancelSelected
        #expect(s.key == .delete)
        #expect(s.modifiers == .command)
        #expect(s.id == "export.cancel")
    }

    // MARK: - Navigation jump shortcuts

    @Test("jumpOnDemand shortcut uses ⌘1")
    func jumpOnDemandShortcut() {
        let s = DataExportKeyboardShortcuts.jumpOnDemand
        #expect(s.key == "1")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.jump.ondemand")
    }

    @Test("jumpScheduled shortcut uses ⌘2")
    func jumpScheduledShortcut() {
        let s = DataExportKeyboardShortcuts.jumpScheduled
        #expect(s.key == "2")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.jump.scheduled")
    }

    @Test("jumpGDPR shortcut uses ⌘3")
    func jumpGDPRShortcut() {
        let s = DataExportKeyboardShortcuts.jumpGDPR
        #expect(s.key == "3")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.jump.gdpr")
    }

    @Test("jumpSettings shortcut uses ⌘4")
    func jumpSettingsShortcut() {
        let s = DataExportKeyboardShortcuts.jumpSettings
        #expect(s.key == "4")
        #expect(s.modifiers == .command)
        #expect(s.id == "export.jump.settings")
    }

    // MARK: - Sendable conformance (compile-time check via static let)

    @Test("Shortcut struct is Sendable (verified by static storage)")
    func shortcutSendableVerified() {
        // If Shortcut did not conform to Sendable, this would fail to compile.
        let _: [DataExportKeyboardShortcuts.Shortcut] = DataExportKeyboardShortcuts.all
        #expect(DataExportKeyboardShortcuts.all.count > 0)
    }

    // MARK: - Jump shortcuts cover all ExportKind cases

    @Test("Navigation jump shortcuts cover all 4 ExportKind cases")
    func jumpShortcutsMatchAllKinds() {
        // There are 4 ExportKind cases and 4 jump shortcuts (⌘1..⌘4)
        let jumpShortcutIds = [
            DataExportKeyboardShortcuts.jumpOnDemand.id,
            DataExportKeyboardShortcuts.jumpScheduled.id,
            DataExportKeyboardShortcuts.jumpGDPR.id,
            DataExportKeyboardShortcuts.jumpSettings.id
        ]
        #expect(jumpShortcutIds.count == ExportKind.allCases.count)
        // All IDs are unique
        #expect(Set(jumpShortcutIds).count == jumpShortcutIds.count)
    }

    // MARK: - DataExportShortcutModifier callback wiring

    @Test("DataExportShortcutModifier onJumpKind receives correct ExportKind")
    func shortcutModifierJumpCallback() {
        var receivedKind: ExportKind? = nil
        let modifier = DataExportShortcutModifier(
            onNewExport: {},
            onDownload: {},
            onShare: {},
            onRefresh: {},
            onCancelSelected: {},
            onJumpKind: { kind in receivedKind = kind }
        )
        modifier.onJumpKind(.scheduled)
        #expect(receivedKind == .scheduled)
    }

    @Test("DataExportShortcutModifier onNewExport fires callback")
    func shortcutModifierNewExportCallback() {
        var fired = false
        let modifier = DataExportShortcutModifier(
            onNewExport: { fired = true },
            onDownload: {},
            onShare: {},
            onRefresh: {},
            onCancelSelected: {},
            onJumpKind: { _ in }
        )
        modifier.onNewExport()
        #expect(fired)
    }

    @Test("DataExportShortcutModifier onRefresh fires callback")
    func shortcutModifierRefreshCallback() {
        var fired = false
        let modifier = DataExportShortcutModifier(
            onNewExport: {},
            onDownload: {},
            onShare: {},
            onRefresh: { fired = true },
            onCancelSelected: {},
            onJumpKind: { _ in }
        )
        modifier.onRefresh()
        #expect(fired)
    }

    @Test("DataExportShortcutModifier onCancelSelected fires callback")
    func shortcutModifierCancelCallback() {
        var fired = false
        let modifier = DataExportShortcutModifier(
            onNewExport: {},
            onDownload: {},
            onShare: {},
            onRefresh: {},
            onCancelSelected: { fired = true },
            onJumpKind: { _ in }
        )
        modifier.onCancelSelected()
        #expect(fired)
    }

    @Test("DataExportShortcutModifier onDownload fires callback")
    func shortcutModifierDownloadCallback() {
        var fired = false
        let modifier = DataExportShortcutModifier(
            onNewExport: {},
            onDownload: { fired = true },
            onShare: {},
            onRefresh: {},
            onCancelSelected: {},
            onJumpKind: { _ in }
        )
        modifier.onDownload()
        #expect(fired)
    }

    @Test("DataExportShortcutModifier onShare fires callback")
    func shortcutModifierShareCallback() {
        var fired = false
        let modifier = DataExportShortcutModifier(
            onNewExport: {},
            onDownload: {},
            onShare: { fired = true },
            onRefresh: {},
            onCancelSelected: {},
            onJumpKind: { _ in }
        )
        modifier.onShare()
        #expect(fired)
    }
}
