import Foundation
import OSLog

// MARK: - §32.1 OSLog levels + privacy annotations reference
//
// This file documents the logging discipline for the BizarreCRM iOS app.
// It is NOT a runtime framework — it's a shared reference and a set of
// SwiftLint-suppressible type aliases / helpers that enforce the rules.
//
// Log levels (§32.1):
//   .debug   — dev-only, COMPILE-STRIPPED in Release builds (via OSLog feature-flag).
//              Used for verbose internal state (request bodies, DB row counts).
//              NEVER log PII at this level — a dev attached to Instruments can see it.
//
//   .info    — lifecycle milestones + meaningful state changes visible in Console.app.
//              Example: "User signed in", "Sync started", "DB opened".
//
//   .notice  — user-visible events: logins / sales / payments.
//              Appears in crash logs + system logs. No PII.
//
//   .error   — recoverable failures (network timeout, parse failure).
//              Always includes `requestID` when available.
//
//   .fault   — unexpected state that should not happen; triggers Apple crash analytics.
//              Reserve for invariant violations and data-integrity issues.
//
// Privacy annotations (§32.6):
//   All dynamic string interpolations in OSLog MUST declare a privacy level:
//
//     privacy: .private   — default for user-derived data (names, emails, notes).
//                           Hidden in console unless device is in dev mode.
//
//     privacy: .public    — safe for IDs, enum states, numeric counts, paths, versions.
//                           Visible in Console.app + crash logs.
//
//   Never use `\(value)` without a `privacy:` annotation on a dynamic value.
//   The SwiftLint rule `osSLogPrivacyRequired` enforces this in CI.
//
// Example (correct):
//   AppLog.networking.info(
//       "Request \(requestId, privacy: .public) → \(statusCode, privacy: .public)"
//   )
//   AppLog.sync.error(
//       "Sync failed: \(AppLog.redacted(rawMessage), privacy: .public) req=\(requestId, privacy: .public)"
//   )
//
// Example (incorrect — NEVER do this):
//   AppLog.auth.debug("Login for \(user.email)")   // ← bare interpolation leaks email

// MARK: - LoggingExamples (compile-time verification only)

#if DEBUG
enum _LoggingDisciplineExamples {
    static func examples() {
        let subsystem = "com.bizarrecrm"
        let logger = Logger(subsystem: subsystem, category: "example")

        // ✓ Public-safe values
        let requestId = "abc123"
        let statusCode = 200
        logger.info("Request \(requestId, privacy: .public) → \(statusCode, privacy: .public)")

        // ✓ Private PII
        let email = "user@example.com"
        logger.debug("Email \(email, privacy: .private)")

        // ✓ Redacted free-form text via LogRedactor before logging
        let rawNote = "Call customer John at 555-1212"
        let redacted = LogRedactor.redact(rawNote)
        logger.info("\(redacted, privacy: .public)")
    }
}
#endif

// MARK: - AppLog convenience extensions (request-ID scoped logging)

extension AppLog {
    /// Log a networking request at `.info` level with the request ID as a public field.
    ///
    /// - Parameters:
    ///   - method: HTTP method string (e.g. "GET").
    ///   - path: Request path (e.g. "/api/v1/tickets"). Never full URL with tokens.
    ///   - requestId: Opaque server request ID from X-Request-ID header.
    public static func logRequest(method: String, path: String, requestId: String?) {
        if let rid = requestId {
            networking.info(
                "→ \(method, privacy: .public) \(path, privacy: .public) req=\(rid, privacy: .public)"
            )
        } else {
            networking.info("→ \(method, privacy: .public) \(path, privacy: .public)")
        }
    }

    /// Log a networking response at `.info` or `.error` depending on status code.
    ///
    /// - Parameters:
    ///   - statusCode: HTTP status code.
    ///   - path: Request path.
    ///   - requestId: Opaque server request ID.
    ///   - durationMs: Round-trip duration in milliseconds.
    public static func logResponse(
        statusCode: Int,
        path: String,
        requestId: String?,
        durationMs: Int
    ) {
        let ridSuffix = requestId.map { " req=\($0)" } ?? ""
        if statusCode >= 400 {
            networking.error(
                "← \(statusCode, privacy: .public) \(path, privacy: .public)\(ridSuffix, privacy: .public) \(durationMs, privacy: .public)ms"
            )
        } else {
            networking.info(
                "← \(statusCode, privacy: .public) \(path, privacy: .public)\(ridSuffix, privacy: .public) \(durationMs, privacy: .public)ms"
            )
        }
    }

    /// Log a sync event at `.notice` with entity + delta count.
    public static func logSyncComplete(entity: String, deltaCount: Int, durationMs: Int) {
        sync.notice(
            "Sync \(entity, privacy: .public) Δ\(deltaCount, privacy: .public) in \(durationMs, privacy: .public)ms"
        )
    }

    /// Log an auth event at `.notice`. Never log PII — only event name + result.
    public static func logAuthEvent(_ event: String, result: String) {
        auth.notice("\(event, privacy: .public) → \(result, privacy: .public)")
    }
}
