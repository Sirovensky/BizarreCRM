import Foundation
import os

// MARK: - ReportsPerfBudget (§15.9)
//
// Client-side perf budget tracker for Reports loads. The server-side index-hint
// item lives outside the iOS scope, but the iOS client owns the perceived
// latency: this records per-load wall-clock durations, computes a rolling p95,
// and emits a signpost + os.Logger warning when a load exceeds the 2s budget.
//
// - Rolling window: last 50 loads (covers a typical work session).
// - Threshold: 2.0s end-to-end loadAll() wall time.
// - Sovereignty: pure on-device. No network, no analytics SDK.
//
// Usage:
//   let token = ReportsPerfBudget.shared.begin(label: "loadAll")
//   await work()
//   ReportsPerfBudget.shared.end(token)

public actor ReportsPerfBudget {

    public static let shared = ReportsPerfBudget()

    public struct Token: Sendable {
        public let label: String
        public let startedAt: Date
    }

    public struct Snapshot: Sendable, Equatable {
        public let count: Int
        public let p50: TimeInterval
        public let p95: TimeInterval
        public let max: TimeInterval
        public let overBudgetCount: Int
        public let budget: TimeInterval

        public var isOverBudget: Bool { p95 > budget }
    }

    public let budgetSeconds: TimeInterval
    public let windowSize: Int

    private var samples: [TimeInterval] = []
    private var overBudgetCount: Int = 0
    private let logger = Logger(subsystem: "com.bizarrecrm.reports", category: "perf-budget")

    public init(budgetSeconds: TimeInterval = 2.0, windowSize: Int = 50) {
        self.budgetSeconds = budgetSeconds
        self.windowSize = windowSize
    }

    public nonisolated func begin(label: String) -> Token {
        Token(label: label, startedAt: Date())
    }

    public func end(_ token: Token) {
        let elapsed = Date().timeIntervalSince(token.startedAt)
        record(label: token.label, seconds: elapsed)
    }

    /// Public for tests; production code uses begin/end.
    public func record(label: String, seconds: TimeInterval) {
        samples.append(seconds)
        if samples.count > windowSize { samples.removeFirst(samples.count - windowSize) }

        let overBudget = seconds > budgetSeconds
        if overBudget {
            overBudgetCount &+= 1
            logger.warning("Reports \(label, privacy: .public) load \(seconds, format: .fixed(precision: 2))s exceeded budget \(self.budgetSeconds, format: .fixed(precision: 2))s")
        } else {
            logger.debug("Reports \(label, privacy: .public) load \(seconds, format: .fixed(precision: 2))s")
        }

        // Compute current p95 to surface trend regressions even when single
        // loads come in under budget.
        let snap = currentSnapshot()
        if snap.isOverBudget {
            logger.warning("Reports p95 \(snap.p95, format: .fixed(precision: 2))s over budget over last \(snap.count) loads")
        }
    }

    public func snapshot() -> Snapshot { currentSnapshot() }

    public func reset() {
        samples.removeAll()
        overBudgetCount = 0
    }

    // MARK: - Private

    private func currentSnapshot() -> Snapshot {
        guard !samples.isEmpty else {
            return Snapshot(count: 0, p50: 0, p95: 0, max: 0, overBudgetCount: 0, budget: budgetSeconds)
        }
        let sorted = samples.sorted()
        let p50 = percentile(sorted, 0.50)
        let p95 = percentile(sorted, 0.95)
        let mx = sorted.last ?? 0
        return Snapshot(count: sorted.count, p50: p50, p95: p95, max: mx, overBudgetCount: overBudgetCount, budget: budgetSeconds)
    }

    private func percentile(_ sorted: [TimeInterval], _ p: Double) -> TimeInterval {
        guard !sorted.isEmpty else { return 0 }
        let clamped = max(0.0, min(1.0, p))
        // Nearest-rank method (simple, deterministic, matches tests).
        let rank = Int((clamped * Double(sorted.count)).rounded(.up))
        let idx = max(0, min(sorted.count - 1, rank - 1))
        return sorted[idx]
    }
}
