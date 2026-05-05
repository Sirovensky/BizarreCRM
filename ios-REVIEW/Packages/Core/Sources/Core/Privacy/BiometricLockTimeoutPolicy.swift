import Foundation
import Observation

// §28 Security & Privacy helpers — Background-enter / foreground re-auth timeout

// MARK: - BiometricLockTimeoutState

/// State machine for the biometric re-auth policy.
public enum BiometricLockTimeoutState: Equatable, Sendable {
    /// The app is active and the session is authenticated.
    case authenticated
    /// The app is in the background; we are tracking elapsed time.
    case backgrounded(since: Date)
    /// The timeout has expired; the caller must prompt for re-auth.
    case requiresReAuthentication
}

// MARK: - BiometricLockTimeoutPolicyProtocol

/// Abstraction for testability.
public protocol BiometricLockTimeoutPolicyProtocol: AnyObject, Sendable {
    var state: BiometricLockTimeoutState { get }
    var requiresReAuthentication: Bool { get }
    func appDidEnterBackground()
    func appWillEnterForeground()
    func markAuthenticated()
}

// MARK: - BiometricLockTimeoutPolicy

/// Observable service that tracks background time and publishes a
/// "requires re-authentication" signal when the app resumes after being
/// backgrounded for longer than `timeout`.
///
/// ## State machine
/// ```
///  authenticated ──(background)──► backgrounded(since: T)
///  backgrounded  ──(foreground, Δt ≤ timeout)──► authenticated
///  backgrounded  ──(foreground, Δt > timeout)──► requiresReAuthentication
///  requiresReAuthentication ──(markAuthenticated)──► authenticated
/// ```
///
/// ## Usage
/// ```swift
/// let policy = BiometricLockTimeoutPolicy(timeout: 5 * 60)
///
/// // Wire to scene-phase changes:
/// .onChange(of: scenePhase) { phase in
///     switch phase {
///     case .background: policy.appDidEnterBackground()
///     case .active:     policy.appWillEnterForeground()
///     default: break
///     }
/// }
///
/// // React to the lock signal:
/// if policy.requiresReAuthentication { showBiometricPrompt() }
/// ```
@Observable
public final class BiometricLockTimeoutPolicy: BiometricLockTimeoutPolicyProtocol, @unchecked Sendable {

    // MARK: - Configuration

    /// Number of seconds the app may remain backgrounded before requiring re-auth.
    public let timeout: TimeInterval

    // MARK: - Observable state

    /// Current policy state.
    public private(set) var state: BiometricLockTimeoutState = .authenticated

    // MARK: - Convenience accessor

    /// `true` when the caller must present a biometric / PIN prompt.
    public var requiresReAuthentication: Bool {
        state == .requiresReAuthentication
    }

    // MARK: - Dependencies (injectable for testing)

    private let now: @Sendable () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - timeout: Seconds before a backgrounded session requires re-auth.
    ///              Defaults to 5 minutes.
    ///   - now:     Current-time provider; defaults to `Date.init`. Inject a
    ///              fixed clock in tests to avoid flakiness.
    public init(
        timeout: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.timeout = timeout
        self.now     = now
    }

    // MARK: - Scene-phase hooks

    /// Call when `ScenePhase` transitions to `.background`.
    public func appDidEnterBackground() {
        guard case .authenticated = state else { return }
        state = .backgrounded(since: now())
    }

    /// Call when `ScenePhase` transitions to `.active`.
    public func appWillEnterForeground() {
        guard case .backgrounded(let since) = state else { return }
        let elapsed = now().timeIntervalSince(since)
        if elapsed > timeout {
            state = .requiresReAuthentication
        } else {
            state = .authenticated
        }
    }

    /// Call after a successful biometric / PIN challenge to clear the lock.
    public func markAuthenticated() {
        state = .authenticated
    }
}
