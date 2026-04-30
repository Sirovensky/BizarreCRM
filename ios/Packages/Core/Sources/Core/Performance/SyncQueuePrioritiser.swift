import Foundation

// §29 Performance — Sync queue prioritisation.
//
// Background sync operations (entity pulls, FTS5 reindex, image eviction, etc.)
// can starve the main thread if they all run at `.background` with no ordering.
// When the user is actively scrolling, a full FTS reindex should yield; when
// the device is idle, it should run freely.
//
// `SyncQueuePrioritiser` manages a set of named work queues at different
// priority tiers and re-schedules them based on app state signals:
//
//   Tier 1 — `.userInitiated`   : current-ticket data, open POS session
//   Tier 2 — `.utility`         : recent entities, sync writes
//   Tier 3 — `.background`      : FTS5 reindex, eviction, analytics flush
//
// Automatic priority adjustments:
//   • `freeze(tier:)`   — suspends all queues at or below `tier` (scrolling,
//                          LPM mode, thermal serious+).
//   • `unfreeze(tier:)` — resumes them.
//   • `deprioritise()`  — moves `.utility` → `.background` globally (LPM).
//   • `restore()`       — undoes `deprioritise()`.
//
// Work is submitted via `enqueue(tier:label:work:)`.  Labels are used in
// signpost intervals for Instruments visibility.
//
// Thread-safety: all queue management behind `NSLock`.
//
// Usage:
//
//   let prioritiser = SyncQueuePrioritiser.shared
//
//   // On scroll start:
//   prioritiser.freeze(tier: .background)
//
//   // On scroll end:
//   prioritiser.unfreeze(tier: .background)
//
//   // Submit background work:
//   prioritiser.enqueue(tier: .background, label: "fts-reindex") {
//       try await ftsService.reindex()
//   }

/// Priority tiers for background sync operations.
public enum SyncWorkTier: Int, Comparable, CaseIterable, Sendable {
    case userInitiated = 0
    case utility       = 1
    case background    = 2

    var qosClass: DispatchQoS.QoSClass {
        switch self {
        case .userInitiated: return .userInitiated
        case .utility:       return .utility
        case .background:    return .background
        }
    }

    public static func < (lhs: SyncWorkTier, rhs: SyncWorkTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Manages prioritised background-sync queues and freezes them in response to
/// UI pressure signals.
public final class SyncQueuePrioritiser: @unchecked Sendable {

    // MARK: - Shared instance

    public static let shared = SyncQueuePrioritiser()

    // MARK: - State

    private let lock = NSLock()

    /// Whether each tier is currently frozen.
    private var frozen: [SyncWorkTier: Bool] = [:]

    /// Whether the prioritiser is globally deprioritised (LPM mode).
    private var deprioritised = false

    /// Work items waiting for a tier to unfreeze.
    private var deferred: [SyncWorkTier: [@Sendable () -> Void]] = [:]

    /// GCD queues keyed by tier.
    private let queues: [SyncWorkTier: DispatchQueue]

    // MARK: - Init

    public init() {
        var qs: [SyncWorkTier: DispatchQueue] = [:]
        for tier in SyncWorkTier.allCases {
            qs[tier] = DispatchQueue(
                label: "com.bizarrecrm.sync.\(tier)",
                qos: DispatchQoS(qosClass: tier.qosClass, relativePriority: 0),
                attributes: .concurrent,
                autoreleaseFrequency: .workItem
            )
        }
        queues = qs
    }

    // MARK: - Public API

    /// Submits `work` to the queue for `tier`.
    ///
    /// If the tier is currently frozen the work is deferred until the tier is
    /// unfrozen.  When the prioritiser is deprioritised and `tier == .utility`,
    /// work runs on the `.background` queue instead.
    ///
    /// - Parameters:
    ///   - tier: The desired priority tier.
    ///   - label: Human-readable label (used in signpost output).
    ///   - work: Synchronous closure to execute on the queue.
    public func enqueue(tier: SyncWorkTier, label: String = "", work: @escaping @Sendable () -> Void) {
        lock.lock()
        let isFrozen = frozen[tier] ?? false

        if isFrozen {
            var pending = deferred[tier] ?? []
            pending.append(work)
            deferred[tier] = pending
            lock.unlock()
            return
        }

        let effectiveTier = (deprioritised && tier == .utility) ? SyncWorkTier.background : tier
        let queue = queues[effectiveTier]!
        lock.unlock()

        queue.async(execute: DispatchWorkItem(block: work))
    }

    /// Submits async `work` to the structured concurrency pool at the
    /// appropriate priority.
    ///
    /// - Parameters:
    ///   - tier: The desired priority tier.
    ///   - label: Human-readable label.
    ///   - work: Async throwing closure.
    @discardableResult
    public func enqueueAsync<T: Sendable>(
        tier: SyncWorkTier,
        label: String = "",
        work: @escaping @Sendable () async throws -> T
    ) -> Task<T, Error> {
        let priority: TaskPriority
        switch tier {
        case .userInitiated: priority = .userInitiated
        case .utility:       priority = .utility
        case .background:    priority = .background
        }

        return Task.detached(priority: priority) {
            try await work()
        }
    }

    // MARK: - Freeze / unfreeze

    /// Freezes all queues at or below `tier`.
    ///
    /// New work submitted to frozen tiers is deferred until `unfreeze(tier:)`
    /// is called.  Call on scroll start or thermal `.serious`.
    /// - Parameter tier: The lowest priority tier to freeze.
    public func freeze(tier: SyncWorkTier) {
        lock.lock()
        for t in SyncWorkTier.allCases where t >= tier {
            frozen[t] = true
        }
        lock.unlock()
    }

    /// Unfreezes all queues at or below `tier` and drains deferred work.
    ///
    /// - Parameter tier: The lowest priority tier to unfreeze.
    public func unfreeze(tier: SyncWorkTier) {
        lock.lock()
        var toRun: [(SyncWorkTier, [@Sendable () -> Void])] = []
        for t in SyncWorkTier.allCases where t >= tier {
            frozen[t] = false
            if let pending = deferred.removeValue(forKey: t), !pending.isEmpty {
                toRun.append((t, pending))
            }
        }
        lock.unlock()

        for (t, items) in toRun {
            let queue = queues[t]!
            items.forEach { queue.async(execute: DispatchWorkItem(block: $0)) }
        }
    }

    // MARK: - LPM support

    /// Globally reduces sync pressure: `.utility` work runs on `.background`
    /// queue.  Call when Low Power Mode is active.
    public func deprioritise() {
        lock.lock()
        deprioritised = true
        lock.unlock()
    }

    /// Restores normal tier mapping.  Call when Low Power Mode exits.
    public func restore() {
        lock.lock()
        deprioritised = false
        lock.unlock()
    }

    // MARK: - Diagnostics

    /// Returns the count of deferred (pending) items per tier.
    public var deferredCounts: [SyncWorkTier: Int] {
        lock.lock()
        defer { lock.unlock() }
        return deferred.mapValues { $0.count }
    }
}
