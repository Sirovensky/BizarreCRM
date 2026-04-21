import Foundation

// MARK: - RateLimiterError

public enum RateLimiterError: Error, Sendable, LocalizedError {
    /// Waited longer than the maximum allowed period.
    case timeout(waitedSeconds: Double)

    public var errorDescription: String? {
        switch self {
        case .timeout(let s):
            return "Rate-limiter timed out after \(Int(s))s waiting for a token."
        }
    }
}

// MARK: - RateLimiter

/// Token-bucket rate limiter (actor-isolated, Swift-6 Sendable).
///
/// **Usage:**
/// ```swift
/// let limiter = RateLimiter(capacity: 60, refillPerSecond: 10)
/// try await limiter.acquire()      // blocks until a token is available
/// // make your network call
/// ```
///
/// **Integration with `APIClient`:**
/// Wire via `RateLimiters.perHost.acquireIfEnabled(host:)` in a middleware
/// wrapper around `APIClientImpl`. Do NOT modify `APIClient.swift` core in
/// this PR — the hook point is documented here:
///
/// ```swift
/// // In a future APIClient+RateLimit.swift:
/// // TODO(§1): Before every perform(...), call:
/// //   try await RateLimiters.perHost.acquire(host: baseURL?.host ?? "")
/// ```
public actor RateLimiter {

    // MARK: - State

    private var tokens: Double
    private let capacity: Double
    private let refillPerSecond: Double
    private var lastRefill: Date
    private var retryAfterUntil: Date?

    /// Maximum time to wait for a token before throwing `.timeout`.
    private static let maxWaitSeconds: Double = 30
    /// Poll interval when waiting for a token (shorter = more responsive, more CPU).
    private static let pollInterval: TimeInterval = 0.1

    // MARK: - Init

    /// - Parameters:
    ///   - capacity: Maximum tokens the bucket can hold. Default: 60.
    ///   - refillPerSecond: Tokens added per second. Default: 10.
    public init(capacity: Int = 60, refillPerSecond: Double = 10) {
        self.capacity = Double(capacity)
        self.refillPerSecond = refillPerSecond
        self.tokens = Double(capacity) // start full
        self.lastRefill = Date()
    }

    // MARK: - Public API

    /// Acquires one token, waiting if the bucket is empty.
    ///
    /// - Throws: `RateLimiterError.timeout` if the wait exceeds 30 seconds.
    public func acquire() async throws {
        let deadline = Date().addingTimeInterval(Self.maxWaitSeconds)

        while true {
            refill()

            // Respect Retry-After backoff first.
            if let retryUntil = retryAfterUntil {
                if Date() < retryUntil {
                    let wait = retryUntil.timeIntervalSinceNow
                    if Date().addingTimeInterval(wait) > deadline {
                        throw RateLimiterError.timeout(waitedSeconds: Self.maxWaitSeconds)
                    }
                    try await Task.sleep(nanoseconds: UInt64(min(wait, Self.pollInterval) * 1_000_000_000))
                    continue
                } else {
                    retryAfterUntil = nil
                }
            }

            if tokens >= 1 {
                tokens -= 1
                return
            }

            // Check timeout before sleeping
            if Date() >= deadline {
                throw RateLimiterError.timeout(waitedSeconds: Self.maxWaitSeconds)
            }
            try await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }

    /// No-op — included for API symmetry with a leaky-bucket variant.
    public func release() {
        // Token bucket: tokens are added by time, not by explicit release.
    }

    /// Backs off the bucket in response to an HTTP 429 `Retry-After` header.
    ///
    /// - Parameter seconds: Value from the server's `Retry-After` header.
    public func applyRetryAfter(_ seconds: Int) {
        let until = Date().addingTimeInterval(TimeInterval(seconds))
        // Only extend the backoff, never shorten it.
        if let existing = retryAfterUntil, existing > until {
            return
        }
        retryAfterUntil = until
        // Drain the bucket so concurrent waiters also block.
        tokens = 0
    }

    // MARK: - Internal

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        guard elapsed > 0 else { return }
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = now
    }
}

// MARK: - RateLimiters (per-host registry)

/// Registry of per-host `RateLimiter` instances.
///
/// **Usage:**
/// ```swift
/// try await RateLimiters.perHost.acquire(host: "api.bizarrecrm.com")
/// ```
public actor RateLimiters {

    /// Shared singleton — the source of truth for all per-host limiters.
    public static let perHost = RateLimiters()

    private var limiters: [String: RateLimiter] = [:]

    private init() {}

    /// Returns the limiter for `host`, creating one on first access.
    public func limiter(for host: String) -> RateLimiter {
        if let existing = limiters[host] { return existing }
        let new = RateLimiter()
        limiters[host] = new
        return new
    }

    /// Acquire a token for `host`.
    ///
    /// This is the integration point for `APIClientImpl` middleware.
    /// Call this before every outbound request to respect per-host limits.
    ///
    /// ```swift
    /// // TODO(§1 integration): In APIClient+RateLimit.swift, wrap perform() with:
    /// //   let host = baseURL?.host ?? "_default"
    /// //   try await RateLimiters.perHost.acquire(host: host)
    /// ```
    public func acquire(host: String) async throws {
        let l = limiter(for: host)
        try await l.acquire()
    }

    /// Apply a `Retry-After` header value for a specific host.
    public func applyRetryAfter(_ seconds: Int, host: String) async {
        let l = limiter(for: host)
        await l.applyRetryAfter(seconds)
    }

    // MARK: - Convenience (enabled flag for gradual rollout)

    /// Whether per-host rate limiting is active. Toggle to `false` in tests
    /// or early Phase 0 if it causes false positives. Default: `true`.
    public var isEnabled: Bool = true

    /// Set the enabled flag (actor-isolated setter).
    public func setEnabled(_ value: Bool) {
        isEnabled = value
    }

    /// Acquire only when `isEnabled`, otherwise no-op.
    /// This is the preferred call site for `APIClientImpl`.
    public func acquireIfEnabled(host: String) async throws {
        guard isEnabled else { return }
        try await acquire(host: host)
    }
}
