import Foundation

// §29.7 Network retry — cancellable backoff token.
//
// `RetryBackoffToken` gives the caller a handle to cancel an in-progress retry
// sequence without cancelling the parent Swift `Task`. This is useful for UI
// flows where a user taps "Cancel" and we want to stop the retry loop
// immediately rather than waiting for the next sleep to time out.
//
// Usage:
// ```swift
// let token = RetryBackoffToken()
// Task {
//     do {
//         let result = try await RetryExecutor(policy: .default)
//             .execute(backoffToken: token) {
//                 try await apiClient.fetchData()
//             }
//     } catch RetryBackoffTokenError.cancelled {
//         // User cancelled — no-op or show toast.
//     }
// }
// // Later, on button tap:
// token.cancel()
// ```

// MARK: - RetryBackoffTokenError

/// Errors specific to the backoff-token cancellation path.
public enum RetryBackoffTokenError: Error, Sendable, Equatable {
    /// The retry loop was cancelled via ``RetryBackoffToken/cancel()``.
    case cancelled
}

// MARK: - RetryBackoffToken

/// A lightweight cancellable handle for an in-progress ``RetryExecutor`` loop.
///
/// Thread-safe: `cancel()` may be called from any thread or Task.
public final class RetryBackoffToken: @unchecked Sendable {

    private let lock = NSLock()
    private var _isCancelled = false

    public init() {}

    /// Cancel the retry loop. Idempotent — subsequent calls are no-ops.
    public func cancel() {
        lock.withLock { _isCancelled = true }
    }

    /// `true` after ``cancel()`` has been called.
    public var isCancelled: Bool {
        lock.withLock { _isCancelled }
    }

    /// Throws ``RetryBackoffTokenError/cancelled`` if the token has been cancelled.
    ///
    /// Called by ``RetryExecutor`` between retry attempts.
    public func checkCancellation() throws {
        if isCancelled {
            throw RetryBackoffTokenError.cancelled
        }
    }
}

// MARK: - RetryExecutor + BackoffToken

public extension RetryExecutor {

    // MARK: Execute with backoff token — HTTP response variant

    /// Execute `operation` with exponential back-off, checking `backoffToken`
    /// between each attempt.
    ///
    /// If `backoffToken.cancel()` is called externally the loop throws
    /// ``RetryBackoffTokenError/cancelled`` at the next inter-attempt check.
    ///
    /// - Parameters:
    ///   - backoffToken: Cancellation handle. Pass a new ``RetryBackoffToken``
    ///     and hold a reference to cancel later.
    ///   - seed: PRNG seed for jitter. Defaults to a time-based value.
    ///   - operation: Work that returns `(T, HTTPURLResponse)`.
    @discardableResult
    func execute<T: Sendable>(
        backoffToken: RetryBackoffToken,
        seed: UInt32 = defaultSeed(),
        operation: @Sendable () async throws -> (T, HTTPURLResponse)
    ) async throws -> (T, HTTPURLResponse) {
        var prng = Mulberry32(seed: seed)
        var lastError: Error = RetryExecutorError.exhausted(underlying: "unknown")

        for attempt in 0 ..< policy.maxAttempts {
            try backoffToken.checkCancellation()

            do {
                let result = try await operation()
                let decision = classifier.classify(response: result.1)
                switch decision {
                case .doNotRetry:
                    return result
                case .retry:
                    lastError = RetryExecutorError.exhausted(underlying: "HTTP \(result.1.statusCode)")
                case .retryAfter(let delay):
                    if attempt < policy.maxAttempts - 1 {
                        try backoffToken.checkCancellation()
                        try await Task.sleep(nanoseconds: sleepNs(delay))
                        continue
                    }
                    lastError = RetryExecutorError.exhausted(underlying: "HTTP 429")
                }
            } catch {
                let decision = classifier.classify(error: error)
                switch decision {
                case .doNotRetry:
                    throw error
                case .retry, .retryAfter:
                    lastError = error
                }
            }

            guard attempt < policy.maxAttempts - 1 else { break }
            try backoffToken.checkCancellation()
            let delay = computedDelay(forAttempt: attempt, prng: &prng)
            try await Task.sleep(nanoseconds: sleepNs(delay))
        }

        throw lastError
    }

    // MARK: Execute with backoff token — simple variant

    /// Execute `operation` with exponential back-off, checking `backoffToken`
    /// between each attempt.
    @discardableResult
    func execute<T: Sendable>(
        backoffToken: RetryBackoffToken,
        seed: UInt32 = defaultSeed(),
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var prng = Mulberry32(seed: seed)
        var lastError: Error = RetryExecutorError.exhausted(underlying: "unknown")

        for attempt in 0 ..< policy.maxAttempts {
            try backoffToken.checkCancellation()

            do {
                return try await operation()
            } catch {
                let decision = classifier.classify(error: error)
                switch decision {
                case .doNotRetry:
                    throw error
                case .retry, .retryAfter:
                    lastError = error
                }
            }

            guard attempt < policy.maxAttempts - 1 else { break }
            try backoffToken.checkCancellation()
            let delay = computedDelay(forAttempt: attempt, prng: &prng)
            try await Task.sleep(nanoseconds: sleepNs(delay))
        }

        throw lastError
    }

    // MARK: Private helper

    private func sleepNs(_ seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}
