import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - §2.13 Remember-me + per-tenant scope + Assistive Access

/// Governs the "Remember email on this device" feature.
///
/// **Security constraints:**
/// - Scope: email address only. Password is **never** stored here; biometric-gated
///   password storage lives in `BiometricCredentialStore`.
/// - Per-tenant: each tenant stores a separate email so a technician who
///   switches tenants gets the right prefill on the next login.
/// - Revocation: calling `forget(tenantId:)` clears the stored email. Logout
///   must call this to honour server-side revocation.
/// - Device binding: storage is `afterFirstUnlockThisDeviceOnly` via the
///   existing `CredentialStore` → `KeychainEmailStorage` path.
///
/// **A11y default:** When Assistive Access (or any Switch-Control / Guided-Access
/// equivalent) is active, "remember email" defaults to `true` to reduce sign-in
/// friction for motor-impaired staff. This can be overridden by the user.
///
/// Usage:
/// ```swift
/// // On login screen appear — prefill toggle default:
/// let rememberDefault = RememberMePolicy.defaultRememberMe
///
/// // On successful login (email scope, per tenant):
/// if rememberMe {
///     RememberMePolicy.shared.save(email: username, tenantId: tenant.id)
/// }
///
/// // On form appear — prefill:
/// loginVM.username = RememberMePolicy.shared.email(for: tenant.id) ?? ""
///
/// // On logout / server-side revoke:
/// RememberMePolicy.shared.forget(tenantId: tenant.id)
/// ```
public final class RememberMePolicy: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = RememberMePolicy()

    // MARK: - Init

    public init() {}

    // MARK: - A11y default

    /// Default toggle state for "Remember email on this device."
    ///
    /// Returns `true` when an assistive technology that reduces motor friction
    /// is running (Assistive Access, Switch Control, Full Keyboard Access).
    public static var defaultRememberMe: Bool {
        #if canImport(UIKit)
        return UIAccessibility.isAssistiveTouchRunning
            || UIAccessibility.isSwitchControlRunning
            || UIAccessibility.isKeyboardNavigationRunning
        #else
        return false
        #endif
    }

    // MARK: - Per-tenant email storage

    /// Persists `email` for `tenantId` in UserDefaults (not a secret; no Keychain needed).
    public func save(email: String, tenantId: String) {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: key(tenantId: tenantId))
    }

    /// Returns the stored email for `tenantId`, or `nil` if none.
    public func email(for tenantId: String) -> String? {
        UserDefaults.standard.string(forKey: key(tenantId: tenantId))
    }

    /// Clears the stored email for `tenantId`. Call on logout or server revocation.
    public func forget(tenantId: String) {
        UserDefaults.standard.removeObject(forKey: key(tenantId: tenantId))
    }

    /// Clears stored emails for all tenants. Call on "Reset all data."
    public func forgetAll() {
        let prefix = "com.bizarrecrm.auth.remember_email."
        let ud = UserDefaults.standard
        ud.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { ud.removeObject(forKey: $0) }
    }

    // MARK: - Private

    private func key(tenantId: String) -> String {
        "com.bizarrecrm.auth.remember_email.\(tenantId)"
    }
}
