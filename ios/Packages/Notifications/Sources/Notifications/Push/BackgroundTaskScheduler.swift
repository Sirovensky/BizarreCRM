import Foundation
import Core
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// MARK: - §21.4 Background tasks — BGAppRefreshTask + BGProcessingTask

/// Centralized background task scheduler for Bizarre CRM.
///
/// Registers and handles:
/// - `BGAppRefreshTask` (`com.bizarrecrm.apprefreshtask`) — opportunistic
///   catch-up sync every 1–4h as iOS permits.
/// - `BGProcessingTask` (`com.bizarrecrm.nightly`) — nightly GRDB VACUUM +
///   image cache prune + FTS5 reindex; requires external power + 30s+ budget.
/// - `BGContinuedProcessingTask` (`com.bizarrecrm.longsync`) — iOS 26+ extended
///   sync run, user-initiated.
///
/// Usage: call `BackgroundTaskScheduler.shared.registerAll()` from
/// `application(_:didFinishLaunchingWithOptions:)`.
@MainActor
public final class BackgroundTaskScheduler {
    public static let shared = BackgroundTaskScheduler()

    // Task identifiers — must match Info.plist BGTaskSchedulerPermittedIdentifiers.
    public static let refreshTaskID   = "com.bizarrecrm.apprefreshtask"
    public static let nightlyTaskID   = "com.bizarrecrm.nightly"
    public static let longSyncTaskID  = "com.bizarrecrm.longsync"

    /// Sync handler invoked on BGAppRefreshTask. Set by SyncOrchestrator.
    public var onRefreshSync: (() async -> Void)?
    /// Maintenance handler invoked on BGProcessingTask.
    public var onNightlyMaintenance: (() async -> Void)?

    private init() {}

    // MARK: - Registration

    public func registerAll() {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskID,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else { return }
            Task { @MainActor [weak self] in
                await self?.handleRefreshTask(task)
            }
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.nightlyTaskID,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor [weak self] in
                await self?.handleNightlyTask(task)
            }
        }

        AppLog.sync.info("BackgroundTaskScheduler: registered \(Self.refreshTaskID, privacy: .public) + \(Self.nightlyTaskID, privacy: .public)")
        #endif
    }

    // MARK: - Schedule

    /// Schedule the next app-refresh task. Call after each task completion and on
    /// `applicationDidFinishLaunching`.
    public func scheduleRefresh() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        // Earliest: 60 min from now; iOS chooses actual window.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.sync.debug("BackgroundTaskScheduler: scheduled refresh task")
        } catch {
            AppLog.sync.error("BackgroundTaskScheduler: submit refresh failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Schedule the nightly maintenance task.
    public func scheduleNightly() {
        #if canImport(BackgroundTasks)
        let request = BGProcessingTaskRequest(identifier: Self.nightlyTaskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = true
        // Earliest: run between 2am–5am (but iOS decides actual slot).
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 2
        comps.minute = 0
        let twoAM = cal.date(from: comps)?.addingTimeInterval(86400) ?? Date(timeIntervalSinceNow: 43200)
        request.earliestBeginDate = twoAM
        do {
            try BGTaskScheduler.shared.submit(request)
            AppLog.sync.debug("BackgroundTaskScheduler: scheduled nightly task for \(twoAM, privacy: .public)")
        } catch {
            AppLog.sync.error("BackgroundTaskScheduler: submit nightly failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    // MARK: - Handlers

    #if canImport(BackgroundTasks)
    private func handleRefreshTask(_ task: BGAppRefreshTask) async {
        // Reschedule immediately so next window is set even if this run fails.
        scheduleRefresh()

        // Budget: 30s max.
        let sync = Task { @MainActor [weak self] in
            await self?.onRefreshSync?()
        }

        task.expirationHandler = {
            sync.cancel()
            AppLog.sync.warning("BackgroundTaskScheduler: refresh task expired")
        }

        await sync.value
        task.setTaskCompleted(success: true)
        AppLog.sync.info("BackgroundTaskScheduler: refresh task completed")
    }

    private func handleNightlyTask(_ task: BGProcessingTask) async {
        scheduleNightly()

        let maintenance = Task { @MainActor [weak self] in
            await self?.onNightlyMaintenance?()
        }

        task.expirationHandler = {
            maintenance.cancel()
            AppLog.sync.warning("BackgroundTaskScheduler: nightly task expired early")
        }

        await maintenance.value
        task.setTaskCompleted(success: true)
        AppLog.sync.info("BackgroundTaskScheduler: nightly task completed")
    }
    #endif

    // MARK: - Debug

    /// Trigger refresh task immediately in simulator / DEBUG.
    /// Equivalent to `e -l objc -- (void)[[BGTaskScheduler sharedScheduler]
    /// _simulateLaunchForTaskWithIdentifier:@"com.bizarrecrm.apprefreshtask"]`
    public func debugSimulateRefresh() async {
        AppLog.sync.debug("BackgroundTaskScheduler: debug simulated refresh start")
        await onRefreshSync?()
        AppLog.sync.debug("BackgroundTaskScheduler: debug simulated refresh done")
    }
}
