import OSLog

// §28.7 Logging redaction contracts
//
// **Hard rule**: every dynamic parameter passed to `os_log` / `Logger` that
// could carry PII MUST use `privacy: .private`.  Only structured identifiers
// (entity IDs, enum raw values, numeric counts) may use `privacy: .public`.
//
// This file is the single authoritative reference for which field types are
// `.public` vs `.private`.  SwiftLint rule `prefer_log_privacy_private` flags
// any `.info/debug/notice/error/fault` call whose interpolated values do not
// carry an explicit privacy annotation.

/// Marks a value as safe to log publicly (non-PII: IDs, counts, states).
/// Use in `Logger.info("\(myId, privacy: .public)")`.
public typealias PublicLogValue = CustomStringConvertible

/// Documents the privacy contract for log parameters.
///
/// Use as a namespace-level reference; do not instantiate.
public enum LoggingPolicy {

    // MARK: - Public (non-PII)

    /// Entity IDs (ticket, customer, invoice numbers — numeric, no PII).
    /// ```swift
    /// AppLog.sync.info("Synced ticket \(id, privacy: .public)")
    /// ```
    public static let publicFields: [String] = [
        "entity_id", "ticket_id", "customer_id", "invoice_id",
        "appointment_id", "expense_id", "employee_id",
        "sku", "status", "op", "attempt", "count",
        "duration_ms", "app_version", "os_version",
    ]

    // MARK: - Private (PII — must use privacy: .private)

    /// These field types MUST always use `privacy: .private` in log calls.
    /// SwiftLint `prefer_log_privacy_private` enforces this by requiring
    /// explicit privacy annotations and rejecting `.public` on these names.
    public static let privateFields: [String] = [
        // Identity
        "name", "first_name", "last_name", "full_name",
        "email", "phone", "address", "city", "zip", "country",
        "birthday", "dob",
        // Auth / secrets
        "token", "access_token", "refresh_token", "api_key",
        "password", "pin", "otp", "backup_code", "pairing_code",
        "push_token", "apns_token",
        // Device PII
        "imei", "serial", "device_passcode",
        // Financial
        "pan", "card_number", "card_last4", "cvv", "routing",
        // Communication bodies
        "sms_body", "email_body", "note_body", "query",
        "waiver_text", "comment", "review_text",
        // File references that can carry PII
        "filename", "url", "path",
    ]

    // MARK: - Developer-facing documentation

    /// Canonical log call patterns:
    ///
    /// CORRECT — structured, privacy-annotated:
    /// ```swift
    /// AppLog.sync.info("Flushing \(count, privacy: .public) ops for ticket \(ticketId, privacy: .public)")
    /// AppLog.networking.debug("Auth token refreshed for user \(userId, privacy: .private)")
    /// ```
    ///
    /// INCORRECT — never log raw strings without annotation:
    /// ```swift
    /// AppLog.networking.info("Request: \(rawURL)")         // Missing annotation
    /// AppLog.auth.debug("Token: \(tokenValue)")             // PII + missing annotation
    /// ```
    ///
    /// The `LogRedactor.redact(_:)` helper is available for legacy string paths
    /// that can't be immediately migrated to structured `os_log`:
    /// ```swift
    /// AppLog.app.info("\(AppLog.redacted(legacyString), privacy: .public)")
    /// ```
    public static let developerNote = "See §28.7 in ios/ActionPlan.md for the full PII table."
}
