import Foundation
import Observation
import Core
import Networking
import Persistence

/// Phase-0 shell. Per §12, the real implementation observes:
///   - NWPathMonitor
///   - UIApplication.didBecomeActive
///   - silent APNs pushes
///   - user-triggered "Sync now" (BGContinuedProcessingTask on iOS 26)
///   - WebSocket event stream
///   - BGAppRefreshTask
///
/// We stub the interface here so callers compile; the subsystems get wired in
/// Phase 2 once read-only screens exist.
@MainActor
@Observable
public final class SyncManager {
    public static let shared = SyncManager()

    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var pendingCount: Int = 0

    private init() {}

    public func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        AppLog.sync.info("Manual sync triggered")
        // TODO (Phase 2): call /api/v1/sync/since?ts=<lastSyncedAt> and drain sync_queue.
        try? await Task.sleep(nanoseconds: 250_000_000)
        lastSyncedAt = Date()
    }

    public func enqueue(_ op: SyncOp) async {
        pendingCount += 1
        AppLog.sync.info("Enqueued sync op: \(op.kind, privacy: .public)")
        // TODO (Phase 3): insert into sync_queue table.
    }
}

public struct SyncOp: Sendable {
    public let kind: String
    public let payload: Data

    public init(kind: String, payload: Data) {
        self.kind = kind
        self.payload = payload
    }
}
