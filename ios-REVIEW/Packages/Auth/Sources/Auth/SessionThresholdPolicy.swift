import Foundation

// MARK: - §2.13 Session threshold tiers

/// Defines the three escalating re-authentication thresholds.
///
/// | Inactivity | Required action              |
/// |------------|------------------------------|
/// | > 15 min   | Biometric re-auth            |
/// | > 4 h      | Full password re-auth        |
/// | > 30 d     | Full re-auth including email |
///
/// **Sovereignty:** Detection is purely device-local; no server round-trip.
/// Tenant can shorten thresholds via `TenantSessionPolicy`; cannot set longer
/// than the global maxima defined here.
public struct SessionThresholdPolicy: Sendable {

    // MARK: - Global maxima (tenant cannot exceed these)

    public static let maxBiometricTimeout:  TimeInterval = 15 * 60             // 15 min
    public static let maxPasswordTimeout:   TimeInterval = 4 * 60 * 60         // 4 h
    public static let maxFullReauthTimeout: TimeInterval = 30 * 24 * 60 * 60   // 30 d

    // MARK: - Effective thresholds (may be shortened by tenant policy)

    /// Idle seconds before biometric re-auth is required.
    public let biometricTimeout: TimeInterval

    /// Idle seconds before full password re-auth is required.
    public let passwordTimeout: TimeInterval

    /// Idle seconds before full re-auth including email verification.
    public let fullReauthTimeout: TimeInterval

    // MARK: - Init

    /// - Parameters:
    ///   - biometricTimeout:  Default 15 min (900 s). Clamped to (0, 15 min].
    ///   - passwordTimeout:   Default 4 h. Clamped to (biometric, 4 h].
    ///   - fullReauthTimeout: Default 30 d. Clamped to (password, 30 d].
    public init(
        biometricTimeout:  TimeInterval = 15 * 60,
        passwordTimeout:   TimeInterval = 4 * 60 * 60,
        fullReauthTimeout: TimeInterval = 30 * 24 * 60 * 60
    ) {
        // Clamp to global maxima; never allow infinite or negative values.
        self.biometricTimeout  = min(max(60, biometricTimeout),  Self.maxBiometricTimeout)
        self.passwordTimeout   = min(max(biometricTimeout + 60, passwordTimeout),   Self.maxPasswordTimeout)
        self.fullReauthTimeout = min(max(passwordTimeout + 60,  fullReauthTimeout), Self.maxFullReauthTimeout)
    }

    // MARK: - Public API

    /// The re-auth level required given `idleSeconds` of inactivity.
    public func requiredLevel(idleSeconds: TimeInterval) -> ReauthLevel {
        if idleSeconds >= fullReauthTimeout { return .fullWithEmail }
        if idleSeconds >= passwordTimeout   { return .password }
        if idleSeconds >= biometricTimeout  { return .biometric }
        return .none
    }
}

// MARK: - ReauthLevel

/// The level of re-authentication the session manager must demand.
public enum ReauthLevel: Comparable, Sendable {
    /// No re-auth needed; session is fresh.
    case none
    /// Biometric (Face ID / Touch ID) sufficient.
    case biometric
    /// Full password required.
    case password
    /// Full re-auth including email verification (expired long-lived session).
    case fullWithEmail
}
