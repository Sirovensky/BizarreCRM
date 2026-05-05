import Foundation

// §29 Performance — JSON decode budget assertion.
//
// Large JSON payloads decoded synchronously on the main thread are a common
// source of frame drops. This guard wraps `JSONDecoder.decode(_:from:)` with:
//  1. Elapsed-time measurement via `ContinuousClock`.
//  2. `AppLog.perf` logging on every call (DEBUG + RELEASE) so Instruments
//     traces show decode costs without instrumentation overhead.
//  3. A DEBUG `assertionFailure` when the decode exceeds `budgetMs`, surfacing
//     regressions in CI before they reach production.
//
// The guard is intentionally a pure enum (no state). Integrate it in repo /
// view-model layers that decode server responses.
//
// ## Usage
// ```swift
// // Replace:
// let tickets = try JSONDecoder.bizarre.decode([Ticket].self, from: data)
//
// // With:
// let tickets = try JSONDecodeBudgetGuard.decode(
//     [Ticket].self,
//     from: data,
//     using: .bizarre,
//     label: "tickets-list"
// )
// ```

/// Wraps `JSONDecoder.decode` and asserts in DEBUG when decoding exceeds the
/// configured time budget.
public enum JSONDecodeBudgetGuard: Sendable {

    // MARK: - Default budget

    /// Default JSON-decode budget (ms). Matches one 60-fps frame (16.7 ms) for
    /// small payloads. Callers with large payloads should pass a wider budget or
    /// move to a background thread / `Task.detached`.
    public static let defaultBudgetMs: Double = 16.7

    /// Wider budget for large or complex payloads (e.g. bulk-sync responses).
    /// Set to 200 ms — half the "noticeable" threshold per §29 UX guidelines.
    public static let largeBudgetMs: Double = 200.0

    // MARK: - Core API

    /// Decode `type` from `data` using `decoder`, logging elapsed time and
    /// asserting if the budget is exceeded.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to produce.
    ///   - data: Raw JSON bytes.
    ///   - decoder: The `JSONDecoder` instance to use. Defaults to a standard
    ///              snake_case + ISO8601 decoder if not supplied.
    ///   - label: Human-readable label used in log lines (e.g. `"tickets-list"`).
    ///   - budgetMs: Maximum acceptable decode time in milliseconds. Exceeding
    ///               this fires `assertionFailure` in DEBUG builds.
    /// - Returns: The decoded value.
    /// - Throws: Any error thrown by `JSONDecoder.decode`.
    @discardableResult
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder = .init(),
        label: String,
        budgetMs: Double = defaultBudgetMs
    ) throws -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try decoder.decode(type, from: data)
        let elapsedMs = durationToMs(start.duration(to: clock.now))

        AppLog.perf.info(
            "[JSONDecodeBudgetGuard] \(label, privacy: .public) \(data.count, privacy: .public)B → \(String(format: "%.2f", elapsedMs), privacy: .public) ms"
        )

        if elapsedMs > budgetMs {
            let msg = "[JSONDecodeBudgetGuard] \(label) decode exceeded \(String(format: "%.1f", budgetMs)) ms budget: \(String(format: "%.2f", elapsedMs)) ms (\(data.count) bytes)"
            AppLog.perf.warning("\(msg, privacy: .public)")
#if DEBUG
            assertionFailure(msg)
#endif
        }

        return value
    }

    /// Async variant that decodes on a detached background task, then returns
    /// the value to the caller's concurrency context.
    ///
    /// Use this for large payloads (bulk sync, reports) to avoid blocking the
    /// main actor. The budget clock starts at the beginning of the background
    /// task — it measures decode time only, not queue wait.
    ///
    /// - Parameters:
    ///   - type: The `Decodable` type to produce.
    ///   - data: Raw JSON bytes.
    ///   - decoder: The `JSONDecoder` instance to use.
    ///   - label: Label for log output.
    ///   - budgetMs: Maximum acceptable decode time; use ``largeBudgetMs`` for
    ///               big payloads.
    /// - Returns: The decoded value.
    /// - Throws: Any error thrown by `JSONDecoder.decode`.
    public static func decodeAsync<T: Decodable & Sendable>(
        _ type: T.Type,
        from data: Data,
        using decoder: JSONDecoder = .init(),
        label: String,
        budgetMs: Double = largeBudgetMs
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) {
            try JSONDecodeBudgetGuard.decode(
                type,
                from: data,
                using: decoder,
                label: label,
                budgetMs: budgetMs
            )
        }.value
    }

    // MARK: - Private helpers

    private static func durationToMs(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}
