import Foundation
import OSLog

// §29.12 Telemetry perf — signpost interval wrapper for repositories.
//
// Repositories (GRDB `ValueObservation` fetch, cursor-page load, etc.) need
// to emit os_signpost intervals so Instruments can correlate repo work with
// UI hitch traces.
//
// `SignpostInterval` is a zero-allocation helper that:
//   1. Opens a `begin` signpost against the shared `bizarrecrm.perf` log.
//   2. Captures a `ContinuousClock.Instant`.
//   3. On `end()` emits the `end` signpost + logs elapsed ms via `AppLog.perf`.
//   4. Optionally fires `BudgetGuard.check` if a budget operation is supplied.
//
// Structured concurrency flavour: `SignpostInterval.measure(_:operation:body:)`
// wraps async work in a begin/end pair automatically.
//
// Typical repo usage:
//
//   func fetchPage(_ cursor: String?) async throws -> CursorPage<Ticket> {
//       try await SignpostInterval.measure("tickets.fetchPage") {
//           try await apiClient.tickets(cursor: cursor)
//       }
//   }

// MARK: - SignpostInterval

/// A lightweight begin/end signpost wrapper for repository fetch operations.
///
/// ### Fire-and-hold pattern
/// ```swift
/// let interval = SignpostInterval(name: "customers.search")
/// defer { interval.end() }
/// // … do work …
/// ```
///
/// ### Async measure shorthand
/// ```swift
/// let results = try await SignpostInterval.measure("customers.search") {
///     try await repo.search(query: query)
/// }
/// ```
public struct SignpostInterval: Sendable {

    // MARK: - Shared log

    /// Reuses the same subsystem/category as `PerformanceMeasurement` so all
    /// perf signposts appear in the same Instruments lane.
    static let log = OSLog(
        subsystem: "com.bizarrecrm",
        category: "bizarrecrm.perf"
    )

    // MARK: - State

    private let name: StaticString
    private let id: OSSignpostID
    private let start: ContinuousClock.Instant
    /// Optional budget operation.  When set, `end()` calls `BudgetGuard.check`.
    private let budgetOperation: PerformanceOperation?

    // MARK: - Initialiser

    /// Opens the signpost interval immediately.
    ///
    /// - Parameters:
    ///   - name: A static string label visible in Instruments (must be a
    ///     literal — `OSLog` requires a `StaticString` for `os_signpost`).
    ///   - operation: Optional ``PerformanceOperation`` for budget enforcement.
    public init(name: StaticString, operation: PerformanceOperation? = nil) {
        self.name = name
        self.id = OSSignpostID(log: Self.log)
        self.start = ContinuousClock().now
        self.budgetOperation = operation
        os_signpost(.begin, log: Self.log, name: name, signpostID: id)
    }

    // MARK: - End

    /// Closes the signpost interval, logs elapsed ms, and optionally checks the
    /// performance budget.
    ///
    /// - Returns: Elapsed time in milliseconds.
    @discardableResult
    public func end() -> Double {
        let elapsedMs = start.duration(to: ContinuousClock().now).milliseconds
        os_signpost(
            .end,
            log: Self.log,
            name: name,
            signpostID: id,
            "%.2f ms",
            elapsedMs
        )
        AppLog.perf.info(
            "[Signpost] \(String(describing: name), privacy: .public) \(String(format: "%.2f", elapsedMs), privacy: .public) ms"
        )
        if let op = budgetOperation {
            BudgetGuard.check(op, elapsedMs: elapsedMs)
        }
        return elapsedMs
    }

    // MARK: - Async measure

    /// Wraps `body` in a signpost interval and returns its result.
    ///
    /// The interval is closed regardless of whether `body` throws.
    ///
    /// ```swift
    /// let page = try await SignpostInterval.measure("tickets.page") {
    ///     try await apiClient.fetchTickets(cursor: cursor)
    /// }
    /// ```
    @discardableResult
    public static func measure<T: Sendable>(
        _ name: StaticString,
        operation: PerformanceOperation? = nil,
        body: () async throws -> T
    ) async rethrows -> T {
        let interval = SignpostInterval(name: name, operation: operation)
        defer { interval.end() }
        return try await body()
    }

    /// Synchronous variant for non-async repo helpers.
    @discardableResult
    public static func measureSync<T>(
        _ name: StaticString,
        operation: PerformanceOperation? = nil,
        body: () throws -> T
    ) rethrows -> T {
        let interval = SignpostInterval(name: name, operation: operation)
        defer { interval.end() }
        return try body()
    }
}

// MARK: - Duration millisecond helper (local, avoids importing PerformanceMeasurement)

private extension Duration {
    var milliseconds: Double {
        let (sec, atto) = components
        return Double(sec) * 1_000 + Double(atto) / 1e15
    }
}
