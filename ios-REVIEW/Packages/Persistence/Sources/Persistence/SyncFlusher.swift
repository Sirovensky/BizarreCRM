import Foundation
import Core

/// §20.3 — drain worker for `sync_queue`.
///
/// Owns a registry of per-entity handlers (`customer.create`, `ticket.update`,
/// `inventory.create`, …). When the network comes back or the app returns to
/// foreground, `flush()` pulls all due rows from `SyncQueueStore.due(...)`
/// and replays each one against its handler. Success → row deleted.
/// Failure → row is marked failed with the current backoff; after 10 attempts
/// it moves to `sync_dead_letter`.
///
/// Design notes:
///
/// - Handlers are **registered once at app launch** from the domain packages
///   (Customers registers `customer.create` + `customer.update`, Tickets
///   registers its own, etc.). A missing handler is a hard bug, not a soft
///   failure — we promote the row straight to the dead-letter table so we
///   don't loop forever on a row no one can service.
///
/// - Flushing is serial. The queue is typically small (tens of rows at
///   most), and a single-writer DB plus a shared API client means parallel
///   retries would just deadlock on each other. Revisit if we ever see
///   queues > 1k rows.
///
/// - Reachability-driven flushing lives in the caller (usually AppServices)
///   — the flusher itself is network-agnostic.
public actor SyncFlusher {
    public static let shared = SyncFlusher()
    private init() {}

    public typealias Handler = @Sendable (SyncQueueRecord) async throws -> Void

    /// Key format: `"{entity}.{op}"` — matches `SyncQueueRecord.kind`.
    private var handlers: [String: Handler] = [:]
    private var isFlushing = false

    public func register(entity: String, op: String, handler: @escaping Handler) {
        handlers["\(entity).\(op)"] = handler
    }

    public func hasHandler(entity: String, op: String) -> Bool {
        handlers["\(entity).\(op)"] != nil
    }

    /// Outcome of a flush pass. Lets callers decide whether to refresh the
    /// "Just synced N min ago" UI badge — we only want to advance the
    /// `lastSyncedAt` watermark on real success or a no-op (nothing to do).
    public enum FlushOutcome: Sendable, Equatable {
        case empty       // nothing was due
        case allOK       // every due record replayed cleanly
        case partial     // at least one record failed
        case readError   // could not read the due queue
    }

    /// Pull every due record and attempt to replay. Safe to call multiple
    /// times in a row — a second invocation while the first is still
    /// running is a no-op (the single-writer in-flight guard makes the
    /// flusher re-entrancy-safe).
    @discardableResult
    public func flush() async -> FlushOutcome {
        guard !isFlushing else { return .empty }
        isFlushing = true
        defer { isFlushing = false }

        let due: [SyncQueueRecord]
        do {
            due = try await SyncQueueStore.shared.due(limit: 50)
        } catch {
            AppLog.sync.error("flush() failed to read due rows: \(error.localizedDescription, privacy: .public)")
            return .readError
        }
        if due.isEmpty { return .empty }

        AppLog.sync.info("sync flush started — \(due.count) record(s) due")

        var failureCount = 0

        for record in due {
            guard let id = record.id else { continue }
            let kind = record.kind ?? "\(record.entity ?? "unknown").\(record.op ?? "unknown")"

            do {
                try await SyncQueueStore.shared.markInFlight(id)
            } catch {
                AppLog.sync.error("markInFlight failed for \(kind, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failureCount += 1
                continue
            }

            guard let handler = handlers[kind] else {
                // Unknown entity.op — this row will loop forever if we
                // just fail it. Fast-track to dead-letter instead.
                AppLog.sync.error("no handler for \(kind, privacy: .public) — promoting to dead-letter")
                try? await promoteStraightToDeadLetter(id: id)
                failureCount += 1
                continue
            }

            do {
                try await handler(record)
                try await SyncQueueStore.shared.markSucceeded(id)
                AppLog.sync.info("sync replay OK: \(kind, privacy: .public) id=\(id)")
            } catch {
                // Domain handlers should raise a typed error with enough
                // context for the operator; we record the stringified form
                // in `last_error` so the dead-letter inspector can triage.
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                try? await SyncQueueStore.shared.markFailed(id, error: message)
                AppLog.sync.warning("sync replay failed: \(kind, privacy: .public) id=\(id) — \(message, privacy: .public)")
                failureCount += 1
            }
        }

        AppLog.sync.info("sync flush finished — failures=\(failureCount)")
        return failureCount == 0 ? .allOK : .partial
    }

    /// Bump the row's attempt count to `maxAttempts` in a single shot so
    /// `markFailed` tips it into the dead-letter archive. We don't have a
    /// dedicated public API for "promote now" so we round-trip through the
    /// standard failure path.
    private func promoteStraightToDeadLetter(id: Int64) async throws {
        for _ in 0..<SyncQueueStore.maxAttempts {
            try? await SyncQueueStore.shared.markFailed(id, error: "no registered handler")
        }
    }
}
