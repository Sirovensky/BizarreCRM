import Foundation
import OSLog

// §28.9 Pasteboard hygiene — audit-log wrapper for UIPasteboard reads
// on sensitive screens (payment, 2FA, PIN entry, audit-export).

// MARK: - PasteboardAudit

/// Stateless helper that logs an audit entry whenever app code reads from the
/// system pasteboard on a screen that handles sensitive data.
///
/// ## Why this matters
/// iOS 14+ shows a banner ("Allowed X to access your pasteboard") when an app
/// reads `UIPasteboard.general` without a user-initiated `PasteButton`.
/// This helper does NOT silence that banner — it is supplemental: it records
/// *who* read the pasteboard and *which screen* triggered the read, so that
/// tenant administrators have an audit trail in `AuditLogs`.
///
/// ## Usage
/// ```swift
/// let value = UIPasteboard.general.string
/// PasteboardAudit.logRead(screen: "paymentEntry", actor: currentUser)
/// ```
///
/// ## Sensitive screens (require logging)
/// Payment entry, PIN entry, 2FA/OTP entry, audit-export, receipts with PAN last4.
/// Non-sensitive paste (ticket ID, customer name search) does NOT need this wrapper.
public enum PasteboardAudit {

    private static let log = Logger(subsystem: "com.bizarrecrm", category: "pasteboardAudit")

    /// Records that the pasteboard was read on a sensitive screen.
    ///
    /// The entry is written to `OSLog` at the `.notice` (persisted) level so it
    /// is available in Console.app and in diagnostics bundles. A companion
    /// server-side sink will be wired in Phase 11 when the audit-log POST
    /// endpoint is available.
    ///
    /// - Parameters:
    ///   - screen:  A stable identifier for the screen performing the read
    ///              (e.g. `"paymentEntry"`, `"pinEntry"`, `"otpChallenge"`).
    ///   - actor:   The current user's ID or display name, redacted to `.private`
    ///              in production logs.
    ///   - context: Optional free-text context (not logged to OSLog to avoid
    ///              accidental PII; reserved for future structured audit events).
    public static func logRead(
        screen: String,
        actor: String,
        context: String? = nil
    ) {
        // The actor is marked `.private` so it does not appear in public
        // Console output but IS captured in full diagnostics bundles shared
        // by the user (e.g. Feedback Assistant, Settings → Privacy → Analytics).
        let safeScreen = screen  // captured as local to use in interpolation
        let safeActor  = actor
        log.notice("Pasteboard read: screen=\(safeScreen, privacy: .public) actor=\(safeActor, privacy: .private)")
    }

    /// Records that sensitive content was written to the pasteboard and will
    /// auto-expire after `expiresIn` seconds.
    ///
    /// Call this alongside the `UIPasteboard.setItems(_:options:)` call to
    /// maintain a consistent audit trail for both reads and writes.
    ///
    /// - Parameters:
    ///   - screen:    Stable screen identifier.
    ///   - expiresIn: Seconds until the pasteboard item auto-clears.
    public static func logWrite(
        screen: String,
        expiresIn: TimeInterval
    ) {
        let safeScreen  = screen
        let safeExpiry  = expiresIn
        log.notice("Pasteboard write: screen=\(safeScreen, privacy: .public) expires_in=\(safeExpiry, privacy: .public)s")
    }
}
