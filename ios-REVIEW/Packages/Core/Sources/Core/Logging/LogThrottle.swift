import Foundation
import OSLog

// §32.1 Log throttling — prevents identical log lines from flooding OSLog
// during tight retry loops, poll cycles, or repeated error callbacks.
//
// Usage:
// ```swift
// // At call site (module-level or type-level):
// private let throttle = LogThrottle(interval: 5)
//
// // Inside the hot path:
// if throttle.shouldEmit(key: "sync_stall") {
//     AppLog.sync.error("Sync stalled — no delta returned (throttled)")
// }
// ```
//
// Thread-safety: all mutation is serialised on a dedicated `DispatchQueue`.

// MARK: - LogThrottle

/// Suppresses repeat emissions of the same keyed log line within a rolling
/// time window, preventing log spam during tight loops or rapid retries.
///
/// - A distinct `key` string identifies each logical log site.
/// - The first call for a key always emits (`shouldEmit` returns `true`).
/// - Subsequent calls within `interval` seconds return `false`.
/// - After `interval` seconds the gate resets and the next call emits again.
/// - An optional `maxBurst` lets you allow a small burst before throttling.
public final class LogThrottle: @unchecked Sendable {

    // MARK: - Types

    private struct Entry {
        var lastEmitTime: Date
        var burstCount: Int
    }

    // MARK: - Properties

    private let interval: TimeInterval
    private let maxBurst: Int
    private var table: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "com.bizarrecrm.logthrottle", attributes: [])

    // MARK: - Init

    /// Create a throttle with the given suppression window.
    ///
    /// - Parameters:
    ///   - interval: Seconds between allowed emissions for a given key.
    ///     Defaults to 30 s — appropriate for recurring background errors.
    ///   - maxBurst: Number of times the same key may emit consecutively
    ///     before throttling kicks in.  Defaults to 1 (no burst).
    public init(interval: TimeInterval = 30, maxBurst: Int = 1) {
        self.interval = interval
        self.maxBurst = max(1, maxBurst)
    }

    // MARK: - Public API

    /// Returns `true` if the log line identified by `key` should be emitted.
    ///
    /// Call this inline inside an `if` guard around the log statement so
    /// OSLog string interpolation is only evaluated when the gate is open:
    /// ```swift
    /// if throttle.shouldEmit(key: "printer_offline") {
    ///     AppLog.hardware.error("Printer offline (throttled, \(intervalSeconds)s window)")
    /// }
    /// ```
    public func shouldEmit(key: String) -> Bool {
        queue.sync {
            let now = Date()
            if var entry = table[key] {
                let elapsed = now.timeIntervalSince(entry.lastEmitTime)
                if elapsed >= interval {
                    // Window expired — reset burst counter and allow emit.
                    entry.lastEmitTime = now
                    entry.burstCount = 1
                    table[key] = entry
                    return true
                } else if entry.burstCount < maxBurst {
                    entry.burstCount += 1
                    table[key] = entry
                    return true
                }
                return false
            } else {
                table[key] = Entry(lastEmitTime: now, burstCount: 1)
                return true
            }
        }
    }

    /// Immediately reset the throttle gate for `key`, allowing the next
    /// call to `shouldEmit` to return `true` regardless of elapsed time.
    /// Useful after a state transition that makes the previous suppressed
    /// log irrelevant (e.g. reconnection after an offline period).
    public func reset(key: String) {
        queue.sync { _ = table.removeValue(forKey: key) }
    }

    /// Reset all keys.
    public func resetAll() {
        queue.sync { table.removeAll() }
    }
}

// MARK: - AppLog.Throttle shared instances

extension AppLog {
    /// Module-level shared throttle singletons.
    ///
    /// These are convenient defaults; heavy-use modules should own their own
    /// `LogThrottle` instances with tuned intervals.
    public enum Throttle {
        /// 30-second throttle for network/sync error repetition.
        public static let networking = LogThrottle(interval: 30)
        /// 60-second throttle for hardware peripheral errors (printer, terminal).
        public static let hardware   = LogThrottle(interval: 60)
        /// 10-second throttle for UI-layer warnings (accessibility, layout).
        public static let ui         = LogThrottle(interval: 10)
        /// 30-second throttle for background-task log lines.
        public static let bg         = LogThrottle(interval: 30)
    }
}
