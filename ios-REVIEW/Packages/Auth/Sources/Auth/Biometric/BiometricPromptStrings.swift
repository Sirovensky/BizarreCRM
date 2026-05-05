import Foundation
import LocalAuthentication

// §28.10 Biometric auth — localised reason strings for every biometric gate
// in the app. Keeping them here (rather than inline at call sites) makes it
// easy to update copy, translate, and audit that every sensitive action has an
// appropriate human-readable explanation.

// MARK: - BiometricPromptStrings

/// Canonical, localised reason strings passed to `LAContext.evaluatePolicy`.
///
/// Every call site that triggers a biometric challenge **must** use a case from
/// this enum rather than an inline string literal. This makes copy changes and
/// translations a single-file edit, and lets tests assert on known values.
///
/// ## Usage
/// ```swift
/// try await biometricService.evaluate(reason: BiometricPromptStrings.signIn.reason)
/// ```
///
/// ## Personalisation
/// Several cases accept the current ``BiometricGate.Kind`` so the string can
/// say "Face ID" or "Touch ID" where appropriate.  Pass `.none` when the
/// modality is unknown — the string falls back to the generic "biometrics".
public enum BiometricPromptStrings: Sendable {

    // MARK: - Cases

    /// Quick sign-in from the login screen.
    case signIn(kind: BiometricGate.Kind = .none)

    /// Re-authentication before showing sensitive settings (e.g. reset PIN).
    case sensitiveSettings(kind: BiometricGate.Kind = .none)

    /// Gate before executing a void / refund that exceeds the re-auth threshold.
    case voidTransaction(kind: BiometricGate.Kind = .none)

    /// Gate before permanently deleting a customer record.
    case deleteCustomer(kind: BiometricGate.Kind = .none)

    /// Gate before exporting an audit log or GDPR data package.
    case exportAuditData(kind: BiometricGate.Kind = .none)

    /// Gate before revealing a 2FA backup-code list.
    case revealBackupCodes(kind: BiometricGate.Kind = .none)

    /// Gate before allowing a role-elevation action (e.g. manager override).
    case managerOverride(kind: BiometricGate.Kind = .none)

    // MARK: - Localised reason string

    /// The human-readable string shown inside the system biometric prompt sheet.
    ///
    /// The string is intentionally concise — Apple recommends < 60 characters so
    /// it is never truncated on small screens.
    public var reason: String {
        switch self {
        case .signIn(let kind):
            return "Sign in to Bizarre CRM with \(kind.displayName)"
        case .sensitiveSettings(let kind):
            return "Confirm with \(kind.displayName) to change security settings"
        case .voidTransaction(let kind):
            return "Confirm with \(kind.displayName) to void this transaction"
        case .deleteCustomer(let kind):
            return "Confirm with \(kind.displayName) to delete this customer"
        case .exportAuditData(let kind):
            return "Confirm with \(kind.displayName) to export audit data"
        case .revealBackupCodes(let kind):
            return "Confirm with \(kind.displayName) to show backup codes"
        case .managerOverride(let kind):
            return "Manager override — confirm with \(kind.displayName)"
        }
    }
}

// MARK: - BiometricGate.Kind display name (privacy-friendly fallback)

private extension BiometricGate.Kind {
    /// Short display string suitable for embedding in a prompt sentence.
    var displayName: String {
        switch self {
        case .none:    return "biometrics"
        case .touchID: return "Touch ID"
        case .faceID:  return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
}
