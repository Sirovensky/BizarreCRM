import Foundation

// MARK: - §2.13 Tenant-configurable session thresholds

/// Carries the tenant admin's chosen session timeout values as downloaded from
/// the server (`GET /auth/session-policy`).
///
/// **Enforcement rules:**
/// - Tenant-supplied values are clamped by `SessionThresholdPolicy` to the
///   global maxima (biometric ≤ 15 min, password ≤ 4 h, full ≤ 30 d).
/// - Values of `0` or negative are ignored; global defaults apply.
/// - The policy is sovereign: **no server-side idle detection**. All checks
///   happen on-device using the elapsed time since last activity.
///
/// Integration:
/// ```swift
/// // On login / token refresh, fetch and apply tenant policy:
/// let dto = try await api.sessionPolicy()
/// let policy = TenantSessionPolicy(dto: dto).resolved()
/// await sessionTimer.configure(thresholds: policy)
/// ```
public struct TenantSessionPolicy: Sendable, Codable {

    // MARK: - Raw server values (seconds)

    /// Idle seconds before biometric prompt. Server-side key: `biometricTimeoutSeconds`.
    public let biometricTimeoutSeconds: TimeInterval?

    /// Idle seconds before full password required. Server-side key: `passwordTimeoutSeconds`.
    public let passwordTimeoutSeconds: TimeInterval?

    /// Idle seconds before full re-auth with email. Server-side key: `fullReauthTimeoutSeconds`.
    public let fullReauthTimeoutSeconds: TimeInterval?

    /// Whether 2FA is mandatory for owners / managers / admins.
    /// `nil` defers to `TwoFactorRolePolicy.isRequired(for:)` defaults.
    public let require2FAForPrivilegedRoles: Bool?

    /// Optional PIN rotation period in days. `nil` = rotation disabled.
    public let pinRotationDays: Int?

    // MARK: - Init

    public init(
        biometricTimeoutSeconds:    TimeInterval? = nil,
        passwordTimeoutSeconds:     TimeInterval? = nil,
        fullReauthTimeoutSeconds:   TimeInterval? = nil,
        require2FAForPrivilegedRoles: Bool? = nil,
        pinRotationDays:            Int? = nil
    ) {
        self.biometricTimeoutSeconds    = biometricTimeoutSeconds
        self.passwordTimeoutSeconds     = passwordTimeoutSeconds
        self.fullReauthTimeoutSeconds   = fullReauthTimeoutSeconds
        self.require2FAForPrivilegedRoles = require2FAForPrivilegedRoles
        self.pinRotationDays            = pinRotationDays
    }

    // MARK: - Resolved policy

    /// Returns a `SessionThresholdPolicy` with tenant values clamped to global maxima.
    public func resolved() -> SessionThresholdPolicy {
        SessionThresholdPolicy(
            biometricTimeout:  biometricTimeoutSeconds  ?? SessionThresholdPolicy.maxBiometricTimeout,
            passwordTimeout:   passwordTimeoutSeconds   ?? SessionThresholdPolicy.maxPasswordTimeout,
            fullReauthTimeout: fullReauthTimeoutSeconds ?? SessionThresholdPolicy.maxFullReauthTimeout
        )
    }
}

// MARK: - APIClient extension

import Networking

public extension APIClient {
    /// GET `/api/v1/auth/session-policy`
    ///
    /// Returns the tenant-configured session thresholds and 2FA requirements.
    func sessionPolicy() async throws -> TenantSessionPolicy {
        try await get("/api/v1/auth/session-policy", as: TenantSessionPolicy.self)
    }
}
