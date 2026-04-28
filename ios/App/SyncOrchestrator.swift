import Foundation
import Observation
import Core
import Networking
import Persistence
import UIKit

/// §20.3 — app-level glue between `Reachability`, foreground lifecycle, and
/// `SyncFlusher`. The flusher itself is network-agnostic; this file decides
/// when to call `flush()`.
///
/// Trigger matrix:
///
/// | Signal                     | Action             |
/// | -------------------------- | ------------------ |
/// | App cold-start, online     | flush once at boot |
/// | Reachability flips online  | flush              |
/// | App returns to foreground  | flush              |
/// | Pending count > 0 + online | flush every 60s    |
///
/// Domain packages register their handlers during `AppServices.init` so this
/// orchestrator only kicks the drain — it never owns domain logic.
@MainActor
final class SyncOrchestrator {
    static let shared = SyncOrchestrator()

    private var lastFlushAt: Date?
    private var periodicTask: Task<Void, Never>?
    private var reachabilityTask: Task<Void, Never>?
    private var foregroundTask: Task<Void, Never>?

    /// 60s guard between automatic flushes so a flapping network doesn't
    /// spam the server.
    private let minAutoFlushInterval: TimeInterval = 60

    private init() {}

    func start() {
        startReachabilityWatcher()
        startForegroundWatcher()
        startPeriodicWatcher()
        Task { await flushIfAllowed(reason: "launch") }
    }

    func stop() {
        periodicTask?.cancel(); periodicTask = nil
        reachabilityTask?.cancel(); reachabilityTask = nil
        foregroundTask?.cancel(); foregroundTask = nil
    }

    /// Gate: only flush when online, not while a lockout-style rate limit
    /// would reject us, and not more often than `minAutoFlushInterval`
    /// unless `force` is true.
    private func flushIfAllowed(reason: String, force: Bool = false) async {
        if !Reachability.shared.isOnline {
            AppLog.sync.debug("flush skipped — offline (reason=\(reason, privacy: .public))")
            return
        }
        if !force,
           let last = lastFlushAt,
           Date().timeIntervalSince(last) < minAutoFlushInterval {
            AppLog.sync.debug("flush skipped — throttled (reason=\(reason, privacy: .public))")
            return
        }
        lastFlushAt = Date()
        AppLog.sync.info("flush triggered by \(reason, privacy: .public)")
        let outcome = await SyncFlusher.shared.flush()
        // SyncStatusBadge + StalenessIndicator both poll
        // `UserDefaults.standard.object(forKey: "sync.lastSyncedAt")` to
        // render "Just synced / N min ago / Never synced". Without this
        // write the badge stays "Never synced" forever. Only advance the
        // watermark on a clean run (or a no-op pass) so the UI doesn't lie
        // when individual records failed.
        switch outcome {
        case .allOK, .empty:
            UserDefaults.standard.set(Date(), forKey: "sync.lastSyncedAt")
        case .partial, .readError:
            // Leave the previous timestamp in place — badge will keep showing
            // the older, accurate "N min ago" reading until the next clean run.
            break
        }
    }

    // MARK: - Watchers

    private func startReachabilityWatcher() {
        reachabilityTask?.cancel()
        reachabilityTask = Task { [weak self] in
            // @Observable stream — poll via withObservationTracking for each
            // state flip. Simpler than bridging to an AsyncSequence.
            var wasOnline = Reachability.shared.isOnline
            while !Task.isCancelled {
                let current = Reachability.shared.isOnline
                if current, !wasOnline {
                    await self?.flushIfAllowed(reason: "network-up", force: true)
                }
                wasOnline = current
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func startForegroundWatcher() {
        foregroundTask?.cancel()
        foregroundTask = Task { [weak self] in
            let center = NotificationCenter.default
            let name = UIApplication.willEnterForegroundNotification
            for await _ in center.notifications(named: name).map({ _ in () }) {
                await self?.flushIfAllowed(reason: "foreground", force: true)
            }
        }
    }

    private func startPeriodicWatcher() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(60 * 1_000_000_000))
                if Task.isCancelled { break }
                // Only fire if there's work pending — avoid quiet-state noise.
                let count = (try? await SyncQueueStore.shared.pendingCount()) ?? 0
                if count > 0 {
                    await self?.flushIfAllowed(reason: "periodic")
                }
            }
        }
    }
}
