import Foundation

// §29.3 Image-decode budget guard.
//
// Decoding images off the main thread is already enforced by Nuke, but we
// still want a single chokepoint that:
//  1. Asserts in DEBUG if a synchronous decode call takes > `budgetMs`.
//  2. Logs every decode with its dimension and elapsed time via `AppLog.perf`.
//  3. Provides a `measure(_:)` helper so callers can wrap any decode block.
//
// The guard is intentionally a pure enum (no state) — it wraps the existing
// `BudgetGuard` infrastructure with image-specific context.

/// Wraps image-decode work and checks its duration against the §29 budget.
///
/// ## Usage
/// ```swift
/// let image = ImageDecodeBudgetGuard.measure(label: "thumbnail-42") {
///     ImageDecoder().decode(data)
/// }
/// ```
///
/// The budget defaults to 16.7 ms (one 60-fps frame). For full-res progressive
/// decodes callers may supply a wider budget.
public enum ImageDecodeBudgetGuard: Sendable {

    // MARK: - Default budget

    /// Default maximum decode time (ms). Matches one 60-fps frame.
    public static let defaultBudgetMs: Double = 16.7

    // MARK: - Public API

    /// Measure a synchronous decode block and check it against `budgetMs`.
    ///
    /// - Parameters:
    ///   - label: Human-readable identifier (e.g. `"thumbnail-42"` or `"full-res"`).
    ///   - budgetMs: Maximum acceptable decode time in milliseconds. Defaults to ``defaultBudgetMs``.
    ///   - block: The decode work to execute synchronously.
    /// - Returns: The value produced by `block`.
    @discardableResult
    public static func measure<T>(
        label: String,
        budgetMs: Double = defaultBudgetMs,
        block: () -> T
    ) -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = block()
        let elapsed = start.duration(to: clock.now)
        let elapsedMs = durationToMs(elapsed)

        AppLog.perf.info(
            "[ImageDecodeBudgetGuard] \(label, privacy: .public) decode: \(String(format: "%.2f", elapsedMs), privacy: .public) ms"
        )

        if elapsedMs > budgetMs {
            let msg = "[ImageDecodeBudgetGuard] \(label) decode exceeded \(String(format: "%.1f", budgetMs)) ms budget: \(String(format: "%.2f", elapsedMs)) ms"
            AppLog.perf.warning("\(msg, privacy: .public)")
#if DEBUG
            assertionFailure(msg)
#endif
        }

        return result
    }

    /// Async variant — wraps an off-main-thread decode block.
    ///
    /// Prefer this for full-res decodes to avoid blocking the main actor.
    ///
    /// - Parameters:
    ///   - label: Human-readable label for logging.
    ///   - budgetMs: Budget in milliseconds. Full-res decodes may use 100 ms.
    ///   - block: Async decode work.
    /// - Returns: The value produced by `block`.
    @discardableResult
    public static func measure<T: Sendable>(
        label: String,
        budgetMs: Double = defaultBudgetMs,
        block: @Sendable () async -> T
    ) async -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await block()
        let elapsed = start.duration(to: clock.now)
        let elapsedMs = durationToMs(elapsed)

        AppLog.perf.info(
            "[ImageDecodeBudgetGuard] \(label, privacy: .public) async decode: \(String(format: "%.2f", elapsedMs), privacy: .public) ms"
        )

        if elapsedMs > budgetMs {
            let msg = "[ImageDecodeBudgetGuard] \(label) async decode exceeded \(String(format: "%.1f", budgetMs)) ms budget: \(String(format: "%.2f", elapsedMs)) ms"
            AppLog.perf.warning("\(msg, privacy: .public)")
#if DEBUG
            assertionFailure(msg)
#endif
        }

        return result
    }

    // MARK: - Private helpers

    private static func durationToMs(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}
