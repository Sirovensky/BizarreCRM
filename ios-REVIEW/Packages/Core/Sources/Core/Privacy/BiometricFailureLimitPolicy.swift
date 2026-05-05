import Foundation
import Observation

// §28.10 Biometric auth — Failure-limit policy
//
// After three consecutive biometric failures the app must drop to the
// password / PIN fallback path. iOS itself locks out the biometric sensor
// after five failed Face ID / Touch ID attempts (`LAError.biometryLockout`),
// but our policy is stricter to match §28.10:
//
//     "after 3 fails, drop to password"
//
// The policy is a pure state machine — it does not own the LAContext call.
// Callers wire it like this:
//
// ```swift
// let limit = BiometricFailureLimitPolicy()
//
// do {
//     let ok = try await biometricService.evaluate(reason: "Confirm void")
//     if ok { limit.recordSuccess() } else { limit.recordFailure() }
// } catch {
//     limit.recordFailure()
// }
//
// if limit.requiresPasswordFallback {
//     showPasswordSheet()
//     limit.reset()
// }
// ```

// MARK: - BiometricFailureLimitState

public enum BiometricFailureLimitState: Equatable, Sendable {
    /// Below the failure threshold — biometric is still allowed.
    case allowed(consecutiveFailures: Int)
    /// Threshold reached — caller MUST present the password / PIN fallback.
    case requiresPasswordFallback
}

// MARK: - BiometricFailureLimitPolicyProtocol

public protocol BiometricFailureLimitPolicyProtocol: AnyObject, Sendable {
    @MainActor var state: BiometricFailureLimitState { get }
    @MainActor var requiresPasswordFallback: Bool { get }
    @MainActor func recordSuccess()
    @MainActor func recordFailure()
    @MainActor func reset()
}

// MARK: - BiometricFailureLimitPolicy

/// Counts consecutive biometric failures. After `failureLimit` failures the
/// policy moves to `.requiresPasswordFallback`; the caller must present the
/// password / PIN sheet and call `reset()` once that succeeds.
///
/// A successful biometric evaluation resets the counter immediately.
@Observable
@MainActor
public final class BiometricFailureLimitPolicy: BiometricFailureLimitPolicyProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Number of consecutive failures permitted before falling back. Default 3
    /// per §28.10. Apple's own LAContext lockout fires at 5 — we trip earlier
    /// so the user is offered a graceful PIN path before the sensor itself
    /// goes into lockout.
    public let failureLimit: Int

    // MARK: - Observable state

    public private(set) var state: BiometricFailureLimitState = .allowed(consecutiveFailures: 0)

    public var requiresPasswordFallback: Bool {
        if case .requiresPasswordFallback = state { return true }
        return false
    }

    /// Convenience accessor. Mostly used by tests / debug overlays.
    public var consecutiveFailures: Int {
        switch state {
        case .allowed(let n):              return n
        case .requiresPasswordFallback:    return failureLimit
        }
    }

    // MARK: - Init

    public init(failureLimit: Int = 3) {
        precondition(failureLimit >= 1, "failureLimit must be >= 1")
        self.failureLimit = failureLimit
    }

    // MARK: - Recording

    /// Call after a successful biometric evaluation. Resets the counter.
    public func recordSuccess() {
        state = .allowed(consecutiveFailures: 0)
    }

    /// Call after every biometric failure (cancellation does NOT count — only
    /// authentication failures from `LAError.authenticationFailed`).
    public func recordFailure() {
        switch state {
        case .allowed(let n):
            let next = n + 1
            state = (next >= failureLimit) ? .requiresPasswordFallback : .allowed(consecutiveFailures: next)
        case .requiresPasswordFallback:
            // Already locked into fallback; nothing to do.
            break
        }
    }

    /// Clear the counter. Call after a successful PIN / password fallback.
    public func reset() {
        state = .allowed(consecutiveFailures: 0)
    }
}
