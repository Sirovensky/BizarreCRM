import Foundation
import OSLog

// §29.9 Instruments profile — view-update budget metrics.
//
// SwiftUI's `_printChanges()` shows *which* view fired, but doesn't give you
// a count or timing across many redraws.  `ViewUpdateBudget` fills that gap:
//
//   • Tracks how many times a named view's body was re-evaluated.
//   • Measures wall-clock time per evaluation via `ContinuousClock`.
//   • Compares against a per-view budget threshold and fires `BudgetGuard`
//     (log warning + DEBUG assertionFailure) on violation.
//   • Emits an OSLog counter (`os_signpost(.event)`) so Instruments can plot
//     update frequency on the `bizarrecrm.perf` lane.
//   • Provides a rolling 60-sample window for mean/max/p95 computation.
//
// Usage — call from a View's `body`:
//
//   struct TicketRowView: View {
//       let ticket: Ticket
//       var body: some View {
//           let _ = ViewUpdateBudget.track("TicketRowView", budgetMs: 8)
//           // … heavy row content …
//       }
//   }
//
// Because `track` is called at the top of `body`, it captures both:
//   A. The **frequency** of updates (how often body runs).
//   B. An **approximation** of body cost (time between successive `track`
//      calls for the same label, not the true body duration — but good
//      enough for catching runaway redraws).

// MARK: - ViewUpdateBudget

/// Tracks view body re-evaluation frequency and duration, firing
/// ``BudgetGuard`` on violations.
///
/// All state is stored in a per-label ``Tracker`` accessed via a thread-safe
/// registry.  The registry uses `NSLock` for fast path protection; individual
/// `Tracker` instances use `OSAllocatedUnfairLock` to minimise overhead.
public enum ViewUpdateBudget: Sendable {

    // MARK: - Tracker

    /// Rolling statistics for one named view.
    public final class Tracker: @unchecked Sendable {

        // MARK: - Configuration

        public let label: String
        /// Body evaluations faster than this (ms) do NOT log; only violations fire.
        public let budgetMs: Double

        // MARK: - Rolling window

        /// Fixed-size ring buffer of per-call durations (ms).
        private static let windowSize = 60

        private var _samples: [Double] = []
        private var _sampleIndex: Int = 0
        private var _callCount: Int = 0
        private var _lastCallAt: ContinuousClock.Instant?

        private let lock = NSLock()

        // MARK: - Init

        init(label: String, budgetMs: Double) {
            self.label = label
            self.budgetMs = budgetMs
        }

        // MARK: - Record

        /// Records one body evaluation.  Call at the top of a view's `body`.
        ///
        /// Returns the inter-call duration in ms (time since the previous call),
        /// or `nil` on the first call for this tracker.
        @discardableResult
        func record() -> Double? {
            let now = ContinuousClock().now

            lock.lock()
            _callCount += 1
            let callCount = _callCount
            let previous = _lastCallAt
            _lastCallAt = now
            lock.unlock()

            guard let previous else { return nil }

            let elapsedMs = previous.duration(to: now).milliseconds

            lock.lock()
            if _samples.count < Self.windowSize {
                _samples.append(elapsedMs)
            } else {
                _samples[_sampleIndex % Self.windowSize] = elapsedMs
                _sampleIndex += 1
            }
            lock.unlock()

            // Emit OSLog event for Instruments counter track.
            os_signpost(
                .event,
                log: ViewUpdateBudgetRegistry.log,
                name: "view_update",
                "label=%{public}s count=%d elapsed=%.2f ms",
                label, callCount, elapsedMs
            )

            // Budget check: if updates are extremely frequent (inter-call < budget),
            // the view is re-rendering faster than the budget allows.
            if elapsedMs < budgetMs {
                let message = "[ViewUpdateBudget] \(label) re-rendered in \(String(format: "%.2f", elapsedMs)) ms (budget \(String(format: "%.2f", budgetMs)) ms)"
                AppLog.perf.warning("\(message, privacy: .public)")
#if DEBUG
                // Soft warning — visible in Xcode / test output, not a crash.
                if callCount > 3 {  // skip first few frames on appear
                    assertionFailure(message)
                }
#endif
            }

            return elapsedMs
        }

        // MARK: - Statistics

        /// Total number of body evaluations since this tracker was created.
        public var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _callCount
        }

        /// Mean inter-call duration over the rolling window (ms).
        public var meanMs: Double {
            lock.lock()
            let s = _samples
            lock.unlock()
            guard !s.isEmpty else { return 0 }
            return s.reduce(0, +) / Double(s.count)
        }

        /// Maximum inter-call duration over the rolling window (ms).
        public var maxMs: Double {
            lock.lock()
            let s = _samples
            lock.unlock()
            return s.max() ?? 0
        }

        /// 95th-percentile inter-call duration over the rolling window (ms).
        public var p95Ms: Double {
            lock.lock()
            let s = _samples.sorted()
            lock.unlock()
            guard !s.isEmpty else { return 0 }
            let idx = Int(Double(s.count - 1) * 0.95)
            return s[idx]
        }
    }

    // MARK: - Public API

    /// Records one body evaluation for the named view.
    ///
    /// Call at the very top of a `View.body` using `let _ = …` so the
    /// compiler does not complain about the unused return value:
    ///
    /// ```swift
    /// var body: some View {
    ///     let _ = ViewUpdateBudget.track("TicketRowView", budgetMs: 8.0)
    ///     // … body content …
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - label: Stable identifier for the view type (use the type name).
    ///   - budgetMs: Maximum allowed milliseconds between successive body
    ///     evaluations.  Default `16.7` (one 60 fps frame).  For rows that
    ///     are expected to re-render on every scroll tick, use a tighter value
    ///     such as `8.0`.
    /// - Returns: The inter-call duration in ms, or `nil` on first call.
    @discardableResult
    public static func track(_ label: String, budgetMs: Double = 16.7) -> Double? {
        ViewUpdateBudgetRegistry.shared.tracker(label: label, budgetMs: budgetMs).record()
    }

    /// Returns the `Tracker` for `label` so callers can inspect statistics.
    ///
    /// Creates a new tracker with `budgetMs` if one doesn't exist yet.
    public static func tracker(for label: String, budgetMs: Double = 16.7) -> Tracker {
        ViewUpdateBudgetRegistry.shared.tracker(label: label, budgetMs: budgetMs)
    }

    /// Resets all trackers (call counts, rolling window).  Useful in tests.
    public static func resetAll() {
        ViewUpdateBudgetRegistry.shared.resetAll()
    }
}

// MARK: - ViewUpdateBudgetRegistry (internal)

/// Thread-safe registry of per-label ``ViewUpdateBudget/Tracker`` instances.
final class ViewUpdateBudgetRegistry: @unchecked Sendable {

    static let shared = ViewUpdateBudgetRegistry()

    /// Reuses the `bizarrecrm.perf` log so events appear in the same
    /// Instruments lane as `SignpostInterval` and `PerformanceMeasurement`.
    static let log = OSLog(
        subsystem: "com.bizarrecrm",
        category: "bizarrecrm.perf"
    )

    private let lock = NSLock()
    private var _trackers: [String: ViewUpdateBudget.Tracker] = [:]

    private init() {}

    func tracker(label: String, budgetMs: Double) -> ViewUpdateBudget.Tracker {
        lock.lock()
        defer { lock.unlock() }
        if let existing = _trackers[label] { return existing }
        let t = ViewUpdateBudget.Tracker(label: label, budgetMs: budgetMs)
        _trackers[label] = t
        return t
    }

    func resetAll() {
        lock.lock()
        _trackers.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

// MARK: - Duration millisecond helper

private extension Duration {
    var milliseconds: Double {
        let (sec, atto) = components
        return Double(sec) * 1_000 + Double(atto) / 1e15
    }
}
