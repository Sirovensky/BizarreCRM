import Foundation
import Core

// MARK: - Print Job Queue
//
// `public actor PrintJobQueue` — enqueues print jobs and drains them to the
// configured target printer with exponential backoff retry.
//
// Retry policy:
//   - Max attempts: 3 (configurable via `Policy`).
//   - Backoff:  attempt 1 → 1s, attempt 2 → 2s, attempt 3 → 4s.
//   - Dead-letter: after max attempts the job moves to `deadLetterJobs`.
//
// Thread safety: actor-isolated state; all public API is async.

public actor PrintJobQueue {

    // MARK: Policy

    public struct Policy: Sendable {
        public let maxAttempts: Int
        public let baseBackoffSeconds: Double

        public static let `default` = Policy(maxAttempts: 3, baseBackoffSeconds: 1.0)

        public init(maxAttempts: Int = 3, baseBackoffSeconds: Double = 1.0) {
            self.maxAttempts = max(1, maxAttempts)
            self.baseBackoffSeconds = max(0.1, baseBackoffSeconds)
        }
    }

    // MARK: Enqueued entry

    public struct QueueEntry: Sendable, Identifiable {
        public let id: UUID
        public let job: PrintJob
        public let targetPrinter: Printer
        public var attempts: Int
        public var lastError: String?

        public init(job: PrintJob, targetPrinter: Printer) {
            self.id = job.id
            self.job = job
            self.targetPrinter = targetPrinter
            self.attempts = 0
            self.lastError = nil
        }
    }

    // MARK: State

    private(set) public var pendingJobs: [QueueEntry] = []
    private(set) public var deadLetterJobs: [QueueEntry] = []

    private let engine: any PrintEngine
    private let policy: Policy
    private var isDraining = false

    // MARK: Init

    public init(engine: any PrintEngine, policy: Policy = .default) {
        self.engine = engine
        self.policy = policy
    }

    // MARK: Enqueue

    /// Add a job to the queue and trigger a drain pass.
    ///
    /// If `job.copies > 1`, the same job payload is enqueued `copies` times
    /// as distinct entries (each gets a unique UUID) so the retry policy applies
    /// independently per copy.
    public func enqueue(_ job: PrintJob, to printer: Printer) async {
        let count = max(1, job.copies)
        for copyIndex in 0..<count {
            // Each copy gets a unique UUID so dead-letter management stays per-entry.
            let copyJob: PrintJob
            if copyIndex == 0 {
                copyJob = job   // first copy keeps original UUID (for audit linkage)
            } else {
                copyJob = PrintJob(
                    id: UUID(),
                    kind: job.kind,
                    payload: job.payload,
                    createdAt: job.createdAt,
                    kickDrawer: job.kickDrawer,
                    copies: 1   // each sub-job is a single physical copy
                )
            }
            let entry = QueueEntry(job: copyJob, targetPrinter: printer)
            pendingJobs.append(entry)
        }
        AppLog.hardware.info("PrintJobQueue: enqueued \(job.id, privacy: .public) (\(job.kind.rawValue)) ×\(count). Pending: \(self.pendingJobs.count)")
        await drain()
    }

    // MARK: Manual drain

    /// Re-attempt all pending jobs. Idempotent — safe to call from reconnect handlers.
    public func drain() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while !pendingJobs.isEmpty {
            let index = pendingJobs.startIndex
            var entry = pendingJobs[index]
            pendingJobs.remove(at: index)

            do {
                entry.attempts += 1
                try await engine.print(entry.job, on: entry.targetPrinter)
                AppLog.hardware.info("PrintJobQueue: job \(entry.id, privacy: .public) succeeded on attempt \(entry.attempts)")
            } catch {
                entry.lastError = error.localizedDescription
                AppLog.hardware.warning("PrintJobQueue: job \(entry.id, privacy: .public) failed attempt \(entry.attempts)/\(self.policy.maxAttempts): \(error.localizedDescription, privacy: .public)")

                if entry.attempts < policy.maxAttempts {
                    let backoff = policy.baseBackoffSeconds * pow(2.0, Double(entry.attempts - 1))
                    AppLog.hardware.info("PrintJobQueue: retry in \(backoff)s")
                    // Re-insert at back for fair scheduling; backoff before next pass
                    pendingJobs.append(entry)
                    // Break out of loop to sleep, then re-enter drain
                    isDraining = false
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    isDraining = true
                } else {
                    AppLog.hardware.error("PrintJobQueue: job \(entry.id, privacy: .public) dead-lettered after \(entry.attempts) attempts")
                    deadLetterJobs.append(entry)
                }
            }
        }
    }

    // MARK: Dead-letter management

    /// Retry a specific dead-letter job (re-enqueue it).
    public func retryDeadLetter(id: UUID, to printer: Printer? = nil) async {
        guard let idx = deadLetterJobs.firstIndex(where: { $0.id == id }) else { return }
        var entry = deadLetterJobs.remove(at: idx)
        let targetPrinter = printer ?? entry.targetPrinter
        // Reset attempts so full retry policy applies again
        let freshEntry = QueueEntry(job: entry.job, targetPrinter: targetPrinter)
        pendingJobs.append(freshEntry)
        await drain()
    }

    /// Discard a dead-letter job permanently.
    public func discardDeadLetter(id: UUID) {
        deadLetterJobs.removeAll { $0.id == id }
    }

    /// Discard all dead-letter jobs.
    public func clearDeadLetterQueue() {
        deadLetterJobs.removeAll()
    }

    // MARK: Observation helpers

    public var pendingCount: Int { pendingJobs.count }
    public var deadLetterCount: Int { deadLetterJobs.count }
}
