import Foundation
import Core

/// §18.7 — Background indexing contract for `BGAppRefreshTask` integration.
///
/// The app target registers this task identifier in its `Info.plist` under
/// `BGTaskSchedulerPermittedIdentifiers`:
/// ```
/// com.bizarrecrm.search.reindex
/// ```
///
/// At app launch (or on request), schedule:
/// ```swift
/// BackgroundIndexJob.schedule()
/// ```
///
/// In `BGTaskScheduler.shared.register(forTaskWithIdentifier:…)`:
/// ```swift
/// BackgroundIndexJob.handleTask(bgTask, store: ftsStore, coordinator: reindexCoordinator)
/// ```
///
/// ### Isolation contract
/// This job writes only to the Search package's isolated FTS5 SQLite
/// (`search_fts.sqlite` under App Group). It never touches the main
/// Persistence/GRDB database and makes no network calls.
public enum BackgroundIndexJob {

    public static let taskIdentifier = "com.bizarrecrm.search.reindex"

    // MARK: - Schedule

    /// Schedule the next background reindex. Call on app launch and after
    /// each successful reindex completes.
    public static func schedule() {
        // BGTaskScheduler is only available when the host app has the
        // BGTaskScheduler framework linked. Guard with a runtime availability
        // check so the Search package can compile in test targets that don't
        // link BackgroundTasks.
        scheduleIfAvailable()
    }

    // MARK: - Handle

    /// Call from `BGTaskScheduler.shared.register(forTaskWithIdentifier:…)`.
    ///
    /// - Parameters:
    ///   - store: The `FTSIndexStore` backed by the isolated database.
    ///   - coordinator: The `FTSReindexCoordinator` to drive the rebuild.
    ///   - ticketProvider: Async closure that fetches tickets from the local GRDB cache.
    ///   - customerProvider: Async closure that fetches customers from the local GRDB cache.
    ///   - inventoryProvider: Async closure that fetches inventory items from the local GRDB cache.
    @MainActor
    public static func run(
        coordinator: FTSReindexCoordinator,
        ticketProvider: @Sendable @escaping () async -> [Ticket],
        customerProvider: @Sendable @escaping () async -> [Customer],
        inventoryProvider: @Sendable @escaping () async -> [InventoryItem]
    ) async {
        coordinator.rebuildAll(
            ticketProvider: ticketProvider,
            customerProvider: customerProvider,
            inventoryProvider: inventoryProvider
        )
        // Reschedule for next opportunity.
        schedule()
    }

    // MARK: - Private

    private static func scheduleIfAvailable() {
        // Dynamic lookup avoids hard linking BackgroundTasks framework in Search package.
        // The app target links BackgroundTasks directly and calls schedule() from
        // AppDelegate / App lifecycle — this guard prevents crashes in test environments.
        guard let schedulerClass = NSClassFromString("BGTaskScheduler") as? NSObject.Type,
              schedulerClass.responds(to: NSSelectorFromString("sharedScheduler")) else {
            return
        }
        // Actual scheduling is delegated to the app target which imports BackgroundTasks.
        // See `AppServices.swift` for the concrete BGAppRefreshTaskRequest call.
        AppLog.background.debug(
            "BackgroundIndexJob.schedule() called — actual scheduling deferred to app target",
            privacy: .public
        )
    }
}
