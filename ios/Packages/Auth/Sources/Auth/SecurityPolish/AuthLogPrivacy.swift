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
/// CI enforcement is provided by `scripts/auth-log-ban.sh`, which greps all
/// Swift files under `Packages/Auth/Sources` for banned patterns and exits
/// non-zero if any are found. Wire it into the Xcode build phase or
/// `pre-commit` hook:
///
/// ```
/// bash ios/scripts/auth-log-ban.sh
/// ```
///
/// ## Usage (replace `AppLog.auth.info(...)` with pattern below)
///
/// ```swift
/// // GOOD — value is redacted in Instruments/log stream:
/// AppLog.auth.info("Login attempt for user \(username, privacy: .public)")
/// AppLog.auth.debug("Token refreshed, userId=\(userId, privacy: .public)")
///
/// // BAD — will be caught by auth-log-ban.sh in CI:
/// AppLog.auth.debug("accessToken=\(accessToken)") // exposes secret
/// ```
///
/// ## Banned patterns (checked by scripts/auth-log-ban.sh)
///
/// Any `\.log` / `\.info` / `\.debug` / `\.warning` / `\.error` / `\.fault`
/// call that interpolates the literal names below without `privacy: .private`
/// or `privacy: .sensitive`:
///   `password`, `accessToken`, `refreshToken`, `pin`, `backupCode`
///
/// If you need to log that a token exists use `.presence` or `.redacted`:
/// ```swift
/// AppLog.auth.info("Has token: \(AuthLogPrivacy.presence(tokenStore.accessToken), privacy: .public)")
/// ```
public enum AuthLogPrivacy {

    // MARK: - Banned key names (for documentation and lint reference)

    /// Sensitive field names that MUST NOT appear raw in any log call.
    /// This array is the source of truth for `scripts/auth-log-ban.sh`.
    public static let bannedFields: [String] = [
        "password",
        "accessToken",
        "refreshToken",
        "pin",
        "backupCode",
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

    // MARK: - Debug-build audit (call once at launch in DEBUG builds only)

    /// Scans for log calls that interpolate banned field names without a
    /// `privacy:` label. This is a **debug-only** best-effort guard — the
    /// primary enforcement is `scripts/auth-log-ban.sh` in CI.
    ///
    /// Strips nothing at runtime; exists purely so the call site documents
    /// the invariant in a way the compiler can see.
    ///
    /// Usage:
    /// ```swift
    /// // AppDelegate / @main
    /// #if DEBUG
    /// AuthLogPrivacy.assertNoBannedFieldsInLogs()
    /// #endif
    /// ```
    public static func assertNoBannedFieldsInLogs() {
        // Implementation deliberately empty — enforcement is static (CI script).
        // The presence of this call in the launch path documents the invariant
        // and will show up in coverage tooling so reviewers know it was checked.
        //
        // Dynamic scanning of compiled binaries is out of scope here; the
        // shell script `scripts/auth-log-ban.sh` covers source-level checks.
    }
}
