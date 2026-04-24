import Foundation

// MARK: - RetryPolicy

/// Immutable value type describing how a request should be retried.
///
/// Usage:
/// ```swift
/// let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, maxDelay: 30, jitter: true)
/// ```
public struct RetryPolicy: Sendable, Equatable {

    // MARK: Properties

    /// Maximum number of attempts (initial + retries). Must be ≥ 1.
    public let maxAttempts: Int

    /// Base delay in seconds for the first retry (before exponential scaling).
    public let baseDelay: TimeInterval

    /// Upper bound for any computed delay (before jitter is applied).
    public let maxDelay: TimeInterval

    /// When `true` the executor applies full-jitter (mulberry32) to the delay.
    public let jitter: Bool

    // MARK: Init

    /// - Parameters:
    ///   - maxAttempts: Total attempts including the initial one. Clamped to ≥ 1.
    ///   - baseDelay: Initial backoff seed. Defaults to 0.5 s.
    ///   - maxDelay: Cap on the computed delay. Defaults to 30 s.
    ///   - jitter: Whether to randomise the delay. Defaults to `true`.
    public init(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 0.5,
        maxDelay: TimeInterval = 30,
        jitter: Bool = true
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maxDelay = max(0, maxDelay)
        self.jitter = jitter
    }

    // MARK: Presets

    /// Aggressive default for interactive requests (3 attempts, 0.5 s base, 30 s cap, jitter on).
    public static let `default` = RetryPolicy()

    /// Conservative preset for background / bulk requests.
    public static let conservative = RetryPolicy(maxAttempts: 5, baseDelay: 1, maxDelay: 60)

    /// No retries at all.
    public static let noRetry = RetryPolicy(maxAttempts: 1)

    // MARK: Helpers

    /// Delay for the nth retry attempt (0-indexed, before jitter).
    /// Formula: `min(baseDelay * 2^attempt, maxDelay)`.
    public func exponentialDelay(forAttempt attempt: Int) -> TimeInterval {
        let raw = baseDelay * pow(2.0, Double(attempt))
        return min(raw, maxDelay)
    }
}
