import Foundation
import LocalAuthentication
import Core

// MARK: - LAContext abstraction (for testability)

/// Subset of `LAContext` that the service needs. Tests inject `MockLAContext`.
public protocol LAContextProtocol: Sendable {
    func canEvaluate(policy: LAPolicy) -> (canEvaluate: Bool, error: Error?)
    func evaluate(policy: LAPolicy, localizedReason: String) async throws -> Bool
    var biometryType: LABiometryType { get }
}

// MARK: - Production wrapper

/// Production `LAContextProtocol` backed by a real `LAContext`.
///
/// `LAContext` is not `Sendable`, so we wrap it in an actor-isolated
/// factory that creates a fresh instance per call. Callers must not
/// hold a reference across suspension points.
public struct SystemLAContext: LAContextProtocol, @unchecked Sendable {
    public init() {}

    public func canEvaluate(policy: LAPolicy) -> (canEvaluate: Bool, error: Error?) {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(policy, error: &err)
        return (ok, err)
    }

    public func evaluate(policy: LAPolicy, localizedReason: String) async throws -> Bool {
        let ctx = LAContext()
        return try await ctx.evaluatePolicy(policy, localizedReason: localizedReason)
    }

    public var biometryType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }
}

// MARK: - BiometricGate.Kind Equatable (retroactive, additive)

/// `BiometricGate.Kind` lives in the pre-existing `BiometricGate.swift` and
/// was not originally declared `Equatable`. This retroactive conformance is
/// defined here (in the new Biometric/ layer) so `BiometricAvailability` can
/// synthesise `Equatable` without editing the existing file.
extension BiometricGate.Kind: Equatable {}

// MARK: - Errors

/// Typed errors returned by `BiometricAuthService`.
public enum BiometricAuthError: Error, Sendable, LocalizedError, Equatable {
    /// The device has no biometry hardware, or the user has not enrolled any fingers/face.
    case notAvailable
    /// The user was locked out of biometrics (too many failures).
    case lockedOut
    /// The user explicitly denied the biometric prompt.
    case userCancelled
    /// The app does not have biometric permission (not in Info.plist, or user denied in Settings).
    case permissionDenied
    /// Any other `LAError` — wraps the underlying code for diagnostics.
    case underlyingError(Int)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:     return "Biometric authentication is not available on this device."
        case .lockedOut:        return "Biometrics locked out. Use your PIN to unlock."
        case .userCancelled:    return "Biometric prompt cancelled."
        case .permissionDenied: return "Biometric access was denied. Enable it in Settings."
        case .underlyingError(let code): return "Biometric error (code \(code))."
        }
    }
}

// MARK: - State

/// Observable state of the biometric auth service.
public enum BiometricAvailability: Sendable, Equatable {
    /// Not checked yet.
    case unknown
    /// Hardware present and biometry enrolled.
    case available(kind: BiometricGate.Kind)
    /// Hardware present but no biometry enrolled, or policy check failed.
    case unavailable(reason: BiometricAuthError)
}

// MARK: - Service

/// §2 — Thin, testable LAContext wrapper.
///
/// Owns:
/// - `canEvaluate` — resolves `BiometricAvailability` once per instance
/// - `evaluate(reason:)` — async, typed-error wrapper around
///   `evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, ...)`
///
/// **Design notes**
/// - A new `LAContext` is created per call inside `SystemLAContext` so
///   instance state never leaks between evaluation rounds.
/// - All LAError codes are mapped to `BiometricAuthError` so callers
///   never inspect raw `NSError` domains.
/// - Existing `BiometricGate` (the app-level unlock chain) continues to
///   own the PIN-fallback path; this service is the pure credential-login
///   shortcut layer.
///
/// ## §28.10 Biometric reuse window (30 s)
/// After a successful `evaluate(reason:)` call the timestamp is recorded.
/// A subsequent call within `reuseWindow` seconds returns `.success` without
/// re-prompting the user, so confirm-on-save flows don't double-prompt.
/// The window is intentionally short (30 s) to match the §28.10 spec.
/// Pass `ignoreReuseWindow: true` for destructive / high-value actions
/// (void > $X, delete customer) that always require a fresh challenge.
@MainActor
public final class BiometricAuthService: @unchecked Sendable {

    // MARK: - Public state

    public private(set) var availability: BiometricAvailability = .unknown

    // MARK: - §28.10 Reuse window

    /// Seconds after a successful authentication during which a subsequent
    /// call to `evaluate(reason:)` returns immediately without re-prompting.
    /// §28.10 specifies 30 s.  Injectable for testing.
    public let reuseWindow: TimeInterval

    /// Timestamp of the last successful authentication, or `nil` if none.
    public private(set) var lastAuthenticatedAt: Date?

    /// `true` when a successful authentication occurred within `reuseWindow`
    /// seconds of `now()`.
    public var isWithinReuseWindow: Bool {
        guard let last = lastAuthenticatedAt else { return false }
        return now().timeIntervalSince(last) <= reuseWindow
    }

    // MARK: - Dependencies

    private let context: LAContextProtocol
    private let now: () -> Date

    // MARK: - Init

    /// - Parameters:
    ///   - context: `LAContextProtocol` implementation.  Defaults to the
    ///              production `SystemLAContext`.
    ///   - reuseWindow: Seconds before a re-challenge is needed.  Defaults
    ///                  to 30 as specified in §28.10.
    ///   - now: Clock provider; inject a fixed clock in tests.
    public init(
        context: LAContextProtocol = SystemLAContext(),
        reuseWindow: TimeInterval = 30,
        now: @escaping () -> Date = { Date() }
    ) {
        self.context = context
        self.reuseWindow = reuseWindow
        self.now = now
    }

    // MARK: - canEvaluate

    /// Resolves and caches `availability`. Safe to call multiple times — only
    /// the first call evaluates the policy; subsequent calls return the cached
    /// result.
    ///
    /// - Returns: The resolved `BiometricAvailability`.
    @discardableResult
    public func checkAvailability() -> BiometricAvailability {
        let (ok, rawError) = context.canEvaluate(policy: .deviceOwnerAuthenticationWithBiometrics)

        if ok {
            let kind = biometricKind(from: context.biometryType)
            availability = .available(kind: kind)
        } else {
            let mapped = mapLAError(rawError)
            availability = .unavailable(reason: mapped)
        }
        return availability
    }

    // MARK: - evaluate

    /// Prompts the user for biometric authentication.
    ///
    /// If a successful authentication occurred within `reuseWindow` seconds
    /// and `ignoreReuseWindow` is `false` (the default), the method returns
    /// `true` immediately without re-prompting.  Set `ignoreReuseWindow` to
    /// `true` for destructive or high-value actions (§28.10).
    ///
    /// - Parameters:
    ///   - reason: Localised string shown in the system prompt.
    ///   - ignoreReuseWindow: When `true`, always performs a fresh challenge
    ///     regardless of `lastAuthenticatedAt`.  Defaults to `false`.
    /// - Returns: `true` when authentication succeeded (or was within the
    ///            reuse window).
    /// - Throws: `BiometricAuthError` on any failure.
    public func evaluate(reason: String, ignoreReuseWindow: Bool = false) async throws -> Bool {
        // §28.10 — Return early when within the reuse window.
        if !ignoreReuseWindow, isWithinReuseWindow {
            AppLog.auth.debug("BiometricAuthService: reuse window active — skipping prompt")
            return true
        }

        // Always re-check availability so a runtime change (e.g. the user
        // just enrolled a finger) is reflected without restarting the app.
        let avail = checkAvailability()
        guard case .available = avail else {
            if case .unavailable(let e) = avail { throw e }
            throw BiometricAuthError.notAvailable
        }

        do {
            let result = try await context.evaluate(
                policy: .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if result {
                // Record timestamp for subsequent reuse-window checks.
                lastAuthenticatedAt = now()
            }
            return result
        } catch {
            throw mapLAError(error)
        }
    }

    /// Clears the reuse window timestamp, forcing a fresh challenge on
    /// the next `evaluate(reason:)` call.  Call on session lock or timeout.
    public func invalidateReuseWindow() {
        lastAuthenticatedAt = nil
    }

    // MARK: - Helpers

    private func biometricKind(from type: LABiometryType) -> BiometricGate.Kind {
        switch type {
        case .touchID: return .touchID
        case .faceID:  return .faceID
        case .opticID: return .opticID
        default:       return .none
        }
    }

    private func mapLAError(_ error: Error?) -> BiometricAuthError {
        guard let laError = error as? LAError else {
            return .notAvailable
        }
        switch laError.code {
        case .biometryNotAvailable:            return .notAvailable
        case .biometryNotEnrolled:             return .notAvailable
        case .biometryLockout:                 return .lockedOut
        case .userCancel, .appCancel,
             .systemCancel, .userFallback:     return .userCancelled
        case .authenticationFailed:            return .userCancelled
        default:
            return .underlyingError(laError.errorCode)
        }
    }
}
