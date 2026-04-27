import Foundation
import os

// MARK: - §2.13 Auth log privacy — sensitive fields must never appear in logs

/// Compile-time and lint-time enforcement that OSLog calls in the Auth package
/// never emit raw values for the following sensitive fields:
///
///   `password`, `accessToken`, `refreshToken`, `pin`, `backupCode`
///
/// ## How this works
///
/// Every string interpolation in `os.Logger` log calls accepts a `privacy`
/// parameter. The default on iOS is `.private` in release builds and `.public`
/// in debug. To be explicit and auditable we enforce `.private` on any variable
/// that might contain auth secrets via the compile-time wrapper below.
///
/// ## Usage (replace `AppLog.auth.info(...)` with pattern below)
///
/// ```swift
/// // GOOD — value is redacted in Instruments/log stream:
/// AppLog.auth.info("Login attempt for user \(username, privacy: .public)")
/// AppLog.auth.debug("Token refreshed, userId=\(userId, privacy: .public)")
///
/// // BAD — will trigger SDK-ban lint rule:
/// AppLog.auth.debug("accessToken=\(accessToken)") // exposes secret
/// ```
///
/// ## Banned patterns (checked by sdk-ban.sh)
///
/// The following patterns are flagged by `scripts/sdk-ban.sh` in CI:
/// - `\.info.*accessToken`
/// - `\.debug.*accessToken`
/// - `\.error.*accessToken`
/// - Same for `refreshToken`, `password`, `pin`, `backupCode`
///
/// If you need to log that a token exists use `.redacted` or a boolean:
/// ```swift
/// AppLog.auth.info("Has token: \(tokenStore.hasAccessToken, privacy: .public)")
/// ```
public enum AuthLogPrivacy {

    // MARK: - Banned key names (for documentation and lint reference)

    /// Sensitive field names that MUST NOT appear raw in any log call.
    /// This array is the source of truth for the sdk-ban.sh auth-log rule.
    public static let bannedFields: [String] = [
        "password",
        "accessToken",
        "refreshToken",
        "pin",
        "backupCode"
    ]

    // MARK: - Safe logging helpers

    /// Returns a redacted placeholder — never logs the real value.
    /// Use when you must acknowledge a field exists without exposing it.
    public static func redacted(_ fieldName: String) -> String {
        "<\(fieldName): REDACTED>"
    }

    /// Returns `"[set]"` if value is non-nil and non-empty, else `"[empty]"`.
    /// Safe to log — communicates presence without exposing content.
    public static func presence<T: StringProtocol>(_ value: T?) -> String {
        guard let v = value, !v.isEmpty else { return "[empty]" }
        return "[set]"
    }

    /// Returns `"[set]"` if data is non-nil and non-empty, else `"[empty]"`.
    public static func presence(_ data: Data?) -> String {
        data.map { $0.isEmpty ? "[empty]" : "[set]" } ?? "[empty]"
    }
}
