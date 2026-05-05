import Foundation

// §29 Performance instrumentation — static budget thresholds per operation.
//
// All values are in milliseconds unless noted. They represent the maximum
// acceptable elapsed time for each labelled operation before BudgetGuard emits
// a warning in DEBUG builds.

/// Named performance operations tracked by the performance-instrumentation layer.
public enum PerformanceOperation: String, Sendable, CaseIterable {
    /// Time-to-interactive after cold launch (milliseconds).
    case launchTTI          = "launch_tti"
    /// Frame render budget for smooth 60 fps list scrolling (milliseconds per frame ≈ 16.67 ms).
    case listScroll60fps    = "list_scroll_60fps"
    /// Elapsed time to fully present a detail screen (milliseconds).
    case detailOpenMs       = "detail_open_ms"
    /// Round-trip time for a sale / POS transaction (milliseconds).
    case saleTransactionMs  = "sale_transaction_ms"
    /// Elapsed time for an SMS send operation (milliseconds).
    case smsSendMs          = "sms_send_ms"
}

/// Static budget thresholds (milliseconds) keyed by ``PerformanceOperation``.
///
/// Use ``PerformanceBudget.threshold(for:)`` rather than accessing the table
/// directly so that the zero-budget guard is always enforced.
public enum PerformanceBudget: Sendable {

    // MARK: - Thresholds

    private static let thresholds: [PerformanceOperation: Double] = [
        .launchTTI:          800,   // 800 ms to interactive — above this feels sluggish
        .listScroll60fps:     16.7, // one frame at 60 fps
        .detailOpenMs:       300,   // detail open should feel instant
        .saleTransactionMs: 2_000, // 2 s is the outer limit for a POS tap
        .smsSendMs:         3_000  // 3 s including network round-trip
    ]

    // MARK: - Public API

    /// Returns the budget threshold in milliseconds for `operation`.
    ///
    /// This always returns a positive value — if an operation has no explicit
    /// entry the method returns `Double.infinity` so that BudgetGuard never
    /// fires for unknown operations.
    public static func threshold(for operation: PerformanceOperation) -> Double {
        thresholds[operation] ?? .infinity
    }

    /// `true` when `elapsedMs` is within budget for `operation`.
    public static func isWithinBudget(_ elapsedMs: Double, for operation: PerformanceOperation) -> Bool {
        elapsedMs <= threshold(for: operation)
    }
}
