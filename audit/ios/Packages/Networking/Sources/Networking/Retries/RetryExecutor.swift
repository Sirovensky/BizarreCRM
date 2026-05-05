import Foundation

// MARK: - RetryExecutorError

/// Errors surfaced by `RetryExecutor`.
public enum RetryExecutorError: Error, Sendable, Equatable {
    /// All attempts exhausted. Carries the last underlying error.
    case exhausted(underlying: String)
}

// MARK: - Mulberry32 PRNG

/// A fast, deterministic, splitmix-seeded 32-bit PRNG used for full-jitter.
///
/// Pure value type; callers who need reproducible output supply a fixed seed.
public struct Mulberry32: Sendable {

    private var state: UInt32

    /// - Parameter seed: Initial state. Passing the same seed always produces the same sequence.
    public init(seed: UInt32) {
        self.state = seed
    }

    /// Advance the generator and return the next value in [0, 1).
    public mutating func nextDouble() -> Double {
        state &+= 0x6D2B_79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ (z ^ (z >> 7)) &* (z | 61)
        z ^= z >> 14
        return Double(z) / Double(UInt32.max)
    }
}

// MARK: - RetryExecutor

/// Async helper that runs a throwing closure with exponential back-off and
/// optional full-jitter (mulberry32 seeded).
///
/// This is a pure utility — it has no reference to `APIClient` and callers
/// opt-in explicitly.
///
/// Example:
/// ```swift
/// let result = try await RetryExecutor.execute(policy: .default) {
///     try await urlSession.data(for: request)
/// }
/// ```
public struct RetryExecutor: Sendable {

    // MARK: Properties

    public let policy: RetryPolicy
    public let classifier: RetryClassifier

    // MARK: Init

    public init(
        policy: RetryPolicy = .default,
        classifier: RetryClassifier = RetryClassifier()
    ) {
        self.policy = policy
        self.classifier = classifier
    }

    // MARK: Execute — with HTTP response

    /// Execute `operation` which returns `(T, HTTPURLResponse)`.
    ///
    /// The response is passed to the classifier so 5xx / 429 statuses are
    /// retried without requiring the closure to throw.
    ///
    /// - Parameter seed: PRNG seed for jitter. Defaults to a time-based value.
    @discardableResult
    public func execute<T: Sendable>(
        seed: UInt32 = defaultSeed(),
        operation: @Sendable () async throws -> (T, HTTPURLResponse)
    ) async throws -> (T, HTTPURLResponse) {
        var prng = Mulberry32(seed: seed)
        var lastError: Error = RetryExecutorError.exhausted(underlying: "unknown")

        for attempt in 0 ..< policy.maxAttempts {
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
                        try await Task.sleep(nanoseconds: nanoseconds(for: delay))
                        continue
                    }
                    lastError = RetryExecutorError.exhausted(underlying: "HTTP 429")
                }
            } catch {
                let decision = classifier.classify(error: error)
                switch decision {
                case .doNotRetry:
                    throw error
                case .retry:
                    lastError = error
                case .retryAfter(let delay):
                    if attempt < policy.maxAttempts - 1 {
                        try await Task.sleep(nanoseconds: nanoseconds(for: delay))
                        continue
                    }
                    lastError = error
                }
            }

            // If we reach here there's a retryable condition; sleep before next attempt.
            guard attempt < policy.maxAttempts - 1 else { break }
            let delay = computedDelay(forAttempt: attempt, prng: &prng)
            try await Task.sleep(nanoseconds: nanoseconds(for: delay))
        }

        throw lastError
    }

    // MARK: Execute — simple (no response)

    /// Execute `operation` that throws on failure.
    ///
    /// The classifier uses only the thrown `Error` (no HTTP response context).
    @discardableResult
    public func execute<T: Sendable>(
        seed: UInt32 = defaultSeed(),
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var prng = Mulberry32(seed: seed)
        var lastError: Error = RetryExecutorError.exhausted(underlying: "unknown")

        for attempt in 0 ..< policy.maxAttempts {
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
            let delay = computedDelay(forAttempt: attempt, prng: &prng)
            try await Task.sleep(nanoseconds: nanoseconds(for: delay))
        }

        throw lastError
    }

    // MARK: Convenience static entry-point

    /// One-shot convenience wrapper with the default policy.
    @discardableResult
    public static func execute<T: Sendable>(
        policy: RetryPolicy = .default,
        seed: UInt32 = defaultSeed(),
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await RetryExecutor(policy: policy).execute(seed: seed, operation: operation)
    }

    // MARK: Delay computation

    /// Compute the sleep duration for a given attempt index.
    ///
    /// With jitter disabled: `min(baseDelay * 2^attempt, maxDelay)`
    /// With jitter enabled:  `uniform(0, min(baseDelay * 2^attempt, maxDelay))` (full-jitter)
    func computedDelay(forAttempt attempt: Int, prng: inout Mulberry32) -> TimeInterval {
        let cap = policy.exponentialDelay(forAttempt: attempt)
        guard policy.jitter else { return cap }
        return cap * prng.nextDouble()
    }

    // MARK: Helpers

    private func nanoseconds(for seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}

// MARK: - Default seed

/// Generate a time-based seed for the PRNG.
/// `nonisolated(unsafe)` because `mach_absolute_time` is a pure C call.
@inline(__always)
public func defaultSeed() -> UInt32 {
    let micros = Int64(Date().timeIntervalSinceReferenceDate * 1_000_000)
    return UInt32(truncatingIfNeeded: UInt64(bitPattern: micros))
}
