import Testing
import Foundation
@testable import Settings

// §19 b2 — Tests for SyncDiagnosticsView clear-cache/force-full-sync
// notifications, DeviceModelMap hw.machine lookups, ProfileSettingsViewModel
// slug-copy state, and LogExportSheet construction.

@Suite("§19 b2 — Sync Notifications, DeviceModelMap, SlugCopy, LogExport")
struct Settings§19_b2Tests {

    // MARK: - 1. Notification.Name.forceFullSyncRequested exists

    @Test("forceFullSyncRequested notification name has expected raw value")
    func forceFullSyncRequestedNotificationExists() {
        let name = Notification.Name.forceFullSyncRequested
        #expect(name.rawValue == "com.bizarrecrm.sync.forceFullSyncRequested")
    }

    // MARK: - 2. clearCacheRequested also exists (companion check)

    @Test("clearCacheRequested notification name has expected raw value")
    func clearCacheRequestedNotificationExists() {
        let name = Notification.Name.clearCacheRequested
        #expect(name.rawValue == "com.bizarrecrm.sync.clearCacheRequested")
    }

    // MARK: - 3. DeviceModelMap returns expected name for iPhone16,2

    @Test("DeviceModelMap returns 'iPhone 15 Plus' for identifier 'iPhone16,2'")
    func deviceModelMapKnownIdentifier() {
        let result = DeviceModelMap.name(for: "iPhone16,2")
        #expect(result == "iPhone 15 Plus")
    }

    // MARK: - 4. DeviceModelMap returns nil for unknown identifier

    @Test("DeviceModelMap returns nil for unknown identifier")
    func deviceModelMapUnknownIdentifier() {
        let result = DeviceModelMap.name(for: "Unknown99,9")
        #expect(result == nil)
    }

    // MARK: - 5. ProfileSettingsViewModel slugCopied defaults to false

    @Test("ProfileSettingsViewModel slugCopied defaults to false")
    @MainActor
    func slugCopiedDefaultsFalse() {
        let vm = ProfileSettingsViewModel()
        #expect(vm.slugCopied == false)
    }

    // MARK: - 6. ProfileSettingsViewModel slugCopied can be set to true

    @Test("ProfileSettingsViewModel slugCopied can be toggled true")
    @MainActor
    func slugCopiedCanBeSetTrue() {
        let vm = ProfileSettingsViewModel()
        vm.slugCopied = true
        #expect(vm.slugCopied == true)
    }

    // MARK: - 7. LogEntry is constructible with expected fields

    @Test("LogEntry is constructible and stores all fields")
    func logEntryConstruction() {
        let id = UUID()
        let entry = LogEntry(
            id: id,
            level: "warn",
            timestamp: "2026-04-29T12:00:00Z",
            message: "Sync queue overflowed"
        )
        #expect(entry.id == id)
        #expect(entry.level == "warn")
        #expect(entry.timestamp == "2026-04-29T12:00:00Z")
        #expect(entry.message == "Sync queue overflowed")
    }

    // MARK: - 8. LogExportSheet accepts log entries without crashing

    @Test("LogExportSheet can be initialised with a non-empty entry array")
    func logExportSheetAcceptsEntries() {
        let entries: [LogEntry] = [
            LogEntry(level: "info",  timestamp: "2026-04-29T09:00:00Z", message: "App launched"),
            LogEntry(level: "error", timestamp: "2026-04-29T09:01:00Z", message: "DB migration failed"),
        ]
        // Construction must not throw / crash; verify the passed-through array.
        let sheet = LogExportSheet(entries: entries)
        #expect(sheet.entries.count == 2)
        #expect(sheet.entries[0].level == "info")
        #expect(sheet.entries[1].level == "error")
    }

    // MARK: - 9. LogExportSheet accepts an empty entry array

    @Test("LogExportSheet can be initialised with an empty entry array")
    func logExportSheetAcceptsEmptyEntries() {
        let sheet = LogExportSheet(entries: [])
        #expect(sheet.entries.isEmpty)
    }
}
