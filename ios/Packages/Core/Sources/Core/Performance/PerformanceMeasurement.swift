import Foundation
import OSLog

// §29 Performance instrumentation — os_signpost + OSLog wrapper.
//
// All signposts are emitted on the subsystem/category pair
// `"com.bizarrecrm" / "bizarrecrm.perf"` so that Instruments can filter them
// in a single lane.

/// A thin, `Sendable`-safe wrapper around `os_signpost` and `OSLog` that
/// instruments labelled work items on the `"bizarrecrm.perf"` category.
///
/// ## Usage
/// ```swift
/// let id = PerformanceMeasurement.begin(.launchTTI)
/// // … work …
/// let elapsed = PerformanceMeasurement.end(.launchTTI, id: id)
/// ```
///
/// The type is a `public enum` (no stored state) so it is implicitly
/// `Sendable` without any annotation.
public enum PerformanceMeasurement: Sendable {

    // MARK: - OSLog setup

    /// Shared `OSLog` instance for all performance signposts.
    ///
    /// Using `.default` point-of-interest type keeps the events visible
    /// in the Instruments "Points of Interest" track.
    nonisolated(unsafe) static let log = OSLog(
        subsystem: "com.bizarrecrm",
        category: "bizarrecrm.perf"
    )

    // MARK: - Public API

    /// Emits a `begin` signpost for `operation` and returns a unique
    /// `OSSignpostID` that must be passed to the matching ``end(_:id:)`` call.
    ///
    /// - Parameter operation: The labelled operation being measured.
    /// - Returns: A `OSSignpostID` identifying this specific interval.
    @discardableResult
    public static func begin(_ operation: PerformanceOperation) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "perf", signpostID: id, "%{public}s begin", operation.rawValue)
        return id
    }

    /// Emits an `end` signpost for `operation`, calculates elapsed time using
    /// a `ContinuousClock` measurement, logs the result, and returns the
    /// elapsed time in milliseconds.
    ///
    /// - Parameters:
    ///   - operation: The labelled operation (must match the `begin` call).
    ///   - id: The `OSSignpostID` returned by the matching ``begin(_:)`` call.
    ///   - startedAt: The `ContinuousClock.Instant` captured just before the
    ///     matching `begin` call. Passed explicitly so callers can measure
    ///     work that spans `async` suspension points.
    /// - Returns: Elapsed time in milliseconds.
    @discardableResult
    public static func end(
        _ operation: PerformanceOperation,
        id: OSSignpostID,
        startedAt: ContinuousClock.Instant
    ) -> Double {
        let elapsedMs = startedAt.duration(to: .now).milliseconds
        os_signpost(
            .end,
            log: log,
            name: "perf",
            signpostID: id,
            "%{public}s end %.2f ms",
            operation.rawValue,
            elapsedMs
        )
        AppLog.perf.info(
            "[Perf] \(operation.rawValue, privacy: .public) \(String(format: "%.2f", elapsedMs), privacy: .public) ms"
        )
        return elapsedMs
    }

    /// Convenience overload that captures `now` internally.
    ///
    /// Use this only when you are beginning and ending on the same call site
    /// without crossing an `async` boundary, e.g. for synchronous code blocks.
    ///
    /// - Parameters:
    ///   - operation: The labelled operation.
    ///   - id: The `OSSignpostID` returned by the matching ``begin(_:)`` call.
    ///   - capturedStart: The start instant to use (defaults to `ContinuousClock().now`).
    @discardableResult
    public static func end(
        _ operation: PerformanceOperation,
        id: OSSignpostID,
        capturedStart: ContinuousClock.Instant = ContinuousClock().now
    ) -> Double {
        end(operation, id: id, startedAt: capturedStart)
    }
}

// MARK: - Duration millisecond helper

private extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}
