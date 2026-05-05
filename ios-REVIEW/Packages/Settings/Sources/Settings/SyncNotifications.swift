import Foundation

// §19 — Sync control notification names used by SyncDiagnosticsView
// to trigger cache clearing and forced full re-sync.

public extension Notification.Name {
    /// Posted when the user taps "Clear Cache" in SyncDiagnosticsView.
    static let clearCacheRequested = Notification.Name(
        "com.bizarrecrm.sync.clearCacheRequested"
    )
    /// Posted when the user taps "Force Full Sync" in SyncDiagnosticsView.
    static let forceFullSyncRequested = Notification.Name(
        "com.bizarrecrm.sync.forceFullSyncRequested"
    )
}
