import Foundation

// §29 Performance instrumentation — DEBUG-only budget assertion.
//
// `BudgetGuard.check` emits an `AppLog.perf` warning when a measurement
// exceeds the budget defined in `PerformanceBudget`. In DEBUG builds it also
// fires an `assertionFailure` so that CI test runs surface budget violations
// loudly without ever crashing a production user.

/// Checks elapsed measurements against ``PerformanceBudget`` thresholds.
///
/// - In DEBUG builds: logs a warning **and** fires `assertionFailure` when the
///   budget is exceeded. The assert is a soft warning — it shows up in the Xcode
///   debugger and test output but never terminates the process in production.
/// - In RELEASE builds: only the log line is emitted (no assertion overhead).
///
/// ```swift
/// BudgetGuard.check(.launchTTI, elapsedMs: measuredMs)
/// ```
///
/// `BudgetGuard` is a `public enum` (no stored state) so it is implicitly
/// `Sendable` without any annotation.
public enum BudgetGuard: Sendable {

    /// Evaluates `elapsedMs` against the budget for `operation`.
    ///
    /// - Parameters:
    ///   - operation: The operation that was measured.
    ///   - elapsedMs: Elapsed time in milliseconds.
    public static func check(_ operation: PerformanceOperation, elapsedMs: Double) {
        let budget = PerformanceBudget.threshold(for: operation)
        guard elapsedMs > budget else { return }

        let message = "[BudgetGuard] \(operation.rawValue) exceeded budget: \(String(format: "%.2f", elapsedMs)) ms > \(String(format: "%.2f", budget)) ms"

        AppLog.perf.warning("\(message, privacy: .public)")

#if DEBUG
        assertionFailure(message)
#endif
    }

    /// Returns `true` when `elapsedMs` is within the budget for `operation`.
    ///
    /// This non-throwing predicate is useful in tests that want to verify
    /// budget compliance without triggering `assertionFailure`.
    public static func isWithinBudget(_ elapsedMs: Double, for operation: PerformanceOperation) -> Bool {
        PerformanceBudget.isWithinBudget(elapsedMs, for: operation)
    }
}
