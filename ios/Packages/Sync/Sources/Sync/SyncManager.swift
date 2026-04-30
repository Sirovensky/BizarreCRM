import Foundation
import Network
import Observation
import Core
import Persistence

// MARK: - SyncOpExecutor

/// Host-app-supplied executor. Sync package calls this closure-based
/// protocol; it never imports domain packages.
public protocol SyncOpExecutor: Sendable {
    func execute(_ record: SyncQueueRecord) async throws
}

// MARK: - SyncOp (public convenience type for callers)

public struct SyncOp: Sendable {
    public let op: String
    public let entity: String
    public let entityLocalId: String?
    public let entityServerId: String?
    public let payload: Data
    public let idempotencyKey: String

    public init(
        op: String,
        entity: String,
        entityLocalId: String? = nil,
        entityServerId: String? = nil,
        payload: Data,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.op = op
        self.entity = entity
        self.entityLocalId = entityLocalId
        self.entityServerId = entityServerId
        self.payload = payload
        self.idempotencyKey = idempotencyKey
    }

    // Legacy convenience: kind-based init (keeps old callers compiling).
    public init(kind: String, payload: Data) {
        let parts = kind.split(separator: ".", maxSplits: 1)
        self.entity = parts.count == 2 ? String(parts[0]) : kind
        self.op = parts.count == 2 ? String(parts[1]) : "unknown"
        self.entityLocalId = nil
        self.entityServerId = nil
        self.payload = payload
        self.idempotencyKey = UUID().uuidString
    }

    /// Legacy accessor kept for any call site reading `.kind`.
    public var kind: String { "\(entity).\(op)" }
}

// MARK: - SyncManager

/// Phase-0 real drain loop. Per §20:
///   - `enqueue(_:)` — writes a `SyncQueueRecord` to GRDB.
///   - `syncNow()` — drains up to 20 ready ops, marks success /
///     transient-fail / dead-letter, updates `SyncStateStore` on pull ops.
///   - `autoStart()` — subscribes to NWPathMonitor; triggers `syncNow()`
///     on connectivity restore.
///
/// The Sync package is domain-free: all API calls go through `SyncOpExecutor`
/// injected at app startup. Use `Container.shared.resolve(SyncOpExecutor.self)`
/// in `AppServices`.
@MainActor
@Observable
public final class SyncManager {
    public static let shared = SyncManager()

    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncedAt: Date?
    public private(set) var pendingCount: Int = 0

    // Dead-letter badge count for Settings entry point.
    public private(set) var deadLetterCount: Int = 0

    // Injected by host app (nil → ops logged but not executed).
    public var executor: (any SyncOpExecutor)?

    // NWPathMonitor lives on its own queue.
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bizarrecrm.sync.monitor", qos: .utility)
    private var monitorTask: Task<Void, Never>?

    // Maximum ops drained per syncNow() call.
    private static let drainBatchSize = 20
    // Dead-letter threshold: ops that exceed this attempt count get tombstoned.
    private static let maxAttempts = 5

    private init() {}

    // MARK: - Public API

    /// Write a `SyncQueueRecord` to GRDB and bump the in-memory `pendingCount`.
    public func enqueue(_ op: SyncOp) async {
        let payloadString = String(data: op.payload, encoding: .utf8) ?? ""
        let record = SyncQueueRecord(
            op: op.op,
            entity: op.entity,
            entityLocalId: op.entityLocalId,
            entityServerId: op.entityServerId,
            payload: payloadString,
            idempotencyKey: op.idempotencyKey
        )
        do {
            try await SyncQueueStore.shared.enqueue(record)
            AppLog.sync.info("Enqueued sync op: \(op.kind, privacy: .public)")
            await refreshPendingCount()
        } catch {
            AppLog.sync.error("Failed to enqueue sync op: \(error, privacy: .public)")
        }
    }

    /// Drain up to `drainBatchSize` ready ops.
    /// Called manually (user-triggered) or by `autoStart` on connectivity restore.
    public func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        AppLog.sync.info("syncNow — drain loop start")

        do {
            let ops = try await SyncQueueStore.shared.due(limit: Self.drainBatchSize)
            AppLog.sync.info("Drain: \(ops.count, privacy: .public) ops ready")

            for op in ops {
                guard let id = op.id else { continue }
                await drainSingle(id: id, op: op)
            }

            lastSyncedAt = Date()
            await refreshPendingCount()
            await refreshDeadLetterCount()
        } catch {
            AppLog.sync.error("syncNow error: \(error, privacy: .public)")
        }
    }

    /// Subscribe to NWPathMonitor. Call once from AppServices.
    /// Re-triggers `syncNow()` whenever connectivity is restored.
    public func autoStart() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                Task { @MainActor in
                    AppLog.sync.info("Network restored — triggering drain")
                    await self.syncNow()
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
        AppLog.sync.info("SyncManager autoStart: NWPathMonitor active")
    }

    // MARK: - Internal helpers

    private func drainSingle(id: Int64, op: SyncQueueRecord) async {
        do {
            try await SyncQueueStore.shared.markInFlight(id)

            guard let executor else {
                // No executor wired yet — reschedule as queued.
                AppLog.sync.warning("No SyncOpExecutor — skipping op \(id, privacy: .public)")
                try await SyncQueueStore.shared.markFailed(id, error: "No executor registered")
                return
            }

            try await executor.execute(op)
            try await SyncQueueStore.shared.markSucceeded(id)
            AppLog.sync.debug("Op \(id, privacy: .public) succeeded")

            // If the op was a pull, update SyncStateStore cursor.
            if op.op == "pull", let entity = op.entity {
                try await SyncStateStore.shared.upsert(
                    entity: entity,
                    lastUpdatedAt: Date()
                )
            }

        } catch let appError as AppError {
            await handleAppError(appError, id: id, op: op)
        } catch {
            await handleTransientError(error, id: id, op: op)
        }
    }

    private func handleAppError(_ error: AppError, id: Int64, op: SyncQueueRecord) async {
        switch error {
        case .validation, .conflict:
            // Non-retriable — move to dead letter immediately.
            AppLog.sync.error("Op \(id, privacy: .public) dead-lettered: \(error.localizedDescription, privacy: .public)")
            await forceDeadLetter(id: id, op: op, reason: error.localizedDescription)
        default:
            await handleTransientError(error, id: id, op: op)
        }
    }

    private func handleTransientError(_ error: Error, id: Int64, op: SyncQueueRecord) async {
        let attempts = (op.attemptCount) + 1
        if attempts >= Self.maxAttempts {
            AppLog.sync.error("Op \(id, privacy: .public) exhausted retries — dead letter")
            await forceDeadLetter(id: id, op: op, reason: error.localizedDescription)
        } else {
            do {
                try await SyncQueueStore.shared.markFailed(id, error: error.localizedDescription)
                AppLog.sync.warning("Op \(id, privacy: .public) failed (attempt \(attempts, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            } catch {
                AppLog.sync.error("markFailed threw: \(error, privacy: .public)")
            }
        }
    }

    private func forceDeadLetter(id: Int64, op: SyncQueueRecord, reason: String) async {
        // markFailed with maxAttempts will auto-move to dead_letter table.
        var mutableOp = op
        mutableOp.attemptCount = SyncQueueStore.maxAttempts - 1
        do {
            try await SyncQueueStore.shared.markFailed(id, error: reason)
        } catch {
            AppLog.sync.error("forceDeadLetter markFailed threw: \(error, privacy: .public)")
        }
    }

    private func refreshPendingCount() async {
        do {
            pendingCount = try await SyncQueueStore.shared.pendingCount()
            // Broadcast so PendingActionChip, RetryNowButton, and LastSyncFooter
            // update without a polling timer (§20.8).
            postPendingCountChanged()
        } catch {
            AppLog.sync.error("pendingCount refresh failed: \(error, privacy: .public)")
        }
    }

    private func refreshDeadLetterCount() async {
        do {
            deadLetterCount = try await SyncQueueStore.shared.deadLetterCount()
        } catch {
            AppLog.sync.error("deadLetterCount refresh failed: \(error, privacy: .public)")
        }
    }
}
