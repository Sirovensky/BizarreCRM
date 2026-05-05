import Foundation

// MARK: - §2.13 2FA role requirement

/// Specifies which roles are required to enroll in two-factor authentication.
///
/// Per spec (§2.13):
/// - **Required** for: `owner`, `manager`, `admin`
/// - **Optional** for: all other roles (e.g. `staff`, `technician`, `cashier`)
///
/// The tenant can make 2FA mandatory for additional roles via
/// `TenantSessionPolicy.require2FAForPrivilegedRoles`. When that flag is `true`
/// the default set applies; when `false` 2FA is entirely optional for everyone
/// (e.g. internal-only tenants on a trusted network).
///
/// Usage:
/// ```swift
/// let required = TwoFactorRolePolicy.isRequired(for: user.role,
///                                                tenantPolicy: policy)
/// if required && !user.totpEnabled {
///     // Redirect user to 2FA enrollment before granting full access
/// }
/// ```
public enum TwoFactorRolePolicy {

    // MARK: - Required roles (hardcoded — cannot be relaxed by tenant)

    private static let mandatoryRoles: Set<String> = ["owner", "manager", "admin"]

    // MARK: - Public API

    /// Returns `true` when the user with `role` must enroll in 2FA.
    ///
    /// - Parameters:
    ///   - role:          The user's role string as returned by `GET /auth/me`.
    ///   - tenantPolicy:  Optional tenant policy; `nil` applies the default rules.
    public static func isRequired(
        for role: String,
        tenantPolicy: TenantSessionPolicy? = nil
    ) -> Bool {
        // If tenant explicitly opted out of 2FA enforcement, skip.
        if let policy = tenantPolicy,
           let flag = policy.require2FAForPrivilegedRoles,
           !flag {
            return false
        }
        return mandatoryRoles.contains(role.lowercased())
    }

    /// Roles for which 2FA is required under the global default policy.
    public static var requiredRoles: Set<String> { mandatoryRoles }
}
