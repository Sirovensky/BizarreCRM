import Foundation
import Core

// MARK: - AppBackgroundTaskScheduler (§21.4)
//
// Manages scheduling of BGAppRefreshTask and BGProcessingTask for the app.
//
// Task identifiers (must be registered in Info.plist BGTaskSchedulerPermittedIdentifiers):
//   com.bizarrecrm.sync.refresh        — BGAppRefreshTask (opportunistic, 1–4 h)
//   com.bizarrecrm.maintenance.nightly — BGProcessingTask (GRDB VACUUM + image cache prune)
//
// Usage (from AppServices.swift after DI bootstrap):
// ```swift
// AppBackgroundTaskScheduler.shared.registerAll()
// AppBackgroundTaskScheduler.shared.scheduleIfNeeded()
// ```
//
// The actual BGTaskScheduler calls are performed by the app target which links
// BackgroundTasks. This package provides the identifiers and business logic so
// the app target stays thin.

/// §21.4 — Background task coordinator.
///
/// Scheduling policy:
/// - `BGAppRefreshTask` (sync.refresh): earliest start in 1 hour; budget ≤30 s.
///   Triggers an incremental delta sync and FTS reindex.
/// - `BGProcessingTask` (maintenance.nightly): requires network + power; runs
///   nightly; performs GRDB VACUUM and Nuke image-cache prune.
/// - `BGContinuedProcessingTask` (iOS 26, sync.extended): scheduled only when
///   user explicitly requests "Sync now" from Settings; extended run budget.
public final class AppBackgroundTaskScheduler: @unchecked Sendable {

    // MARK: - Shared

    public static let shared = AppBackgroundTaskScheduler()

    // MARK: - Task identifiers

    public static let syncRefreshID      = "com.bizarrecrm.sync.refresh"
    public static let maintenanceNightlyID = "com.bizarrecrm.maintenance.nightly"
    public static let syncExtendedID     = "com.bizarrecrm.sync.extended"   // iOS 26

    // MARK: - Scheduling hints

    /// Minimum interval before the next opportunistic sync refresh.
    public static let syncRefreshMinInterval: TimeInterval = 60 * 60 // 1 hour

    /// Nominal interval for nightly maintenance.
    public static let maintenanceNightlyInterval: TimeInterval = 60 * 60 * 24 // 24 hours

    // MARK: - Init

    private init() {}

    // MARK: - Schedule

    /// Schedule the sync-refresh and maintenance tasks.
    ///
    /// Call this on every app launch and after each background task completes
    /// so iOS keeps the opportunities flowing.
    ///
    /// The concrete `BGTaskScheduler` calls are in `AppServices.swift` (app
    /// target). This method emits the log entry the app target can pick up
    /// after calling this, then scheduling via BGTaskScheduler.
    public func scheduleIfNeeded() {
        AppLog.app.info(
            "AppBackgroundTaskScheduler: requesting schedule for \(Self.syncRefreshID, privacy: .public) and \(Self.maintenanceNightlyID, privacy: .public)"
        )
        // Actual BGTaskScheduler calls performed by the app target (links BackgroundTasks).
        // See AppServices.swift – scheduleBGTasks().
    }

    // MARK: - Execution handlers

    /// Execute the sync-refresh task.
    ///
    /// Must complete within 30 seconds. Calls `onExpiry` when iOS withdraws
    /// the budget so the caller can cancel outstanding async work.
    ///
    /// - Parameters:
    ///   - onExpiry: Called when the task's `expirationHandler` fires.
    ///   - syncBlock: The delta-sync closure to execute (provided by app target).
    public func runSyncRefresh(
        onExpiry: @escaping @Sendable () -> Void,
        syncBlock: @escaping @Sendable () async -> Void
    ) async {
        // The task budget is ~30 s. Run the sync block; if it exceeds budget
        // the OS calls `expirationHandler` and we stop via `onExpiry`.
        AppLog.app.info("BGAppRefreshTask: sync.refresh starting")
        await withTaskCancellationHandler {
            await syncBlock()
            AppLog.app.info("BGAppRefreshTask: sync.refresh complete — rescheduling")
            scheduleIfNeeded()
        } onCancel: {
            onExpiry()
        }
    }

    /// Execute the nightly maintenance task.
    ///
    /// Requires external power and network (BGProcessingTask semantics).
    /// Runs GRDB VACUUM and Nuke image-cache prune.
    ///
    /// - Parameters:
    ///   - onExpiry: Called when the task's `expirationHandler` fires.
    ///   - maintenanceBlock: Closure provided by app target (calls GRDB VACUUM + cache prune).
    public func runMaintenance(
        onExpiry: @escaping @Sendable () -> Void,
        maintenanceBlock: @escaping @Sendable () async -> Void
    ) async {
        AppLog.app.info("BGProcessingTask: maintenance.nightly starting")
        await withTaskCancellationHandler {
            await maintenanceBlock()
            AppLog.app.info("BGProcessingTask: maintenance.nightly complete")
            scheduleIfNeeded()
        } onCancel: {
            onExpiry()
        }
    }
}
