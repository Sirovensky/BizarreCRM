import Foundation

// §64 — Canonical user-facing error messages per CoreErrorState.
//
// Design notes:
//  - All strings are NSLocalizedString-backed so §27 can translate.
//  - Messages are friendly and actionable — never technical.
//  - Each case provides a `title` (short headline) and `body` (actionable detail).
//  - A `retryLabel` is provided for retryable states.
//  - Pure enum — no stored state, no side effects.

/// Canonical user-facing copy for each `CoreErrorState`.
///
/// Usage:
/// ```swift
/// let copy = ErrorCopy.copy(for: .network)
/// label.text = copy.title
/// detail.text = copy.body
/// ```
public enum ErrorCopy {

    // MARK: — Per-state copy bundle

    public struct Copy: Sendable {
        /// Short headline suitable for an alert title or state view header.
        public let title: String
        /// Actionable detail sentence shown beneath the title.
        public let body: String
        /// Label for the primary action button, or `nil` when no action is offered.
        public let retryLabel: String?
    }

    // MARK: — Accessor

    /// Returns the `Copy` bundle for the given `CoreErrorState`.
    public static func copy(for state: CoreErrorState) -> Copy {
        switch state {
        case .network:
            return Copy(
                title: NSLocalizedString(
                    "error.network.title",
                    value: "Connection Problem",
                    comment: "Error copy — network failure title"
                ),
                body: NSLocalizedString(
                    "error.network.body",
                    value: "We couldn't reach the server. Check your connection and try again.",
                    comment: "Error copy — network failure body"
                ),
                retryLabel: NSLocalizedString(
                    "error.network.retry",
                    value: "Try Again",
                    comment: "Error copy — network failure retry button"
                )
            )

        case .server(let status, let serverMessage):
            let body: String
            if let serverMessage, !serverMessage.isEmpty {
                body = serverMessage
            } else {
                body = NSLocalizedString(
                    "error.server.body",
                    value: "Something went wrong on our end. We're working on it — try again shortly.",
                    comment: "Error copy — server error body (no server message)"
                )
            }
            _ = status // status preserved in associated value; body may surface it via serverMessage
            return Copy(
                title: NSLocalizedString(
                    "error.server.title",
                    value: "Server Error",
                    comment: "Error copy — server error title"
                ),
                body: body,
                retryLabel: NSLocalizedString(
                    "error.server.retry",
                    value: "Try Again",
                    comment: "Error copy — server error retry button"
                )
            )

        case .unauthorized:
            return Copy(
                title: NSLocalizedString(
                    "error.unauthorized.title",
                    value: "Session Expired",
                    comment: "Error copy — 401 title"
                ),
                body: NSLocalizedString(
                    "error.unauthorized.body",
                    value: "Your session has expired. Sign in again to keep working.",
                    comment: "Error copy — 401 body"
                ),
                retryLabel: NSLocalizedString(
                    "error.unauthorized.retry",
                    value: "Sign In",
                    comment: "Error copy — 401 sign-in button"
                )
            )

        case .forbidden:
            return Copy(
                title: NSLocalizedString(
                    "error.forbidden.title",
                    value: "Access Denied",
                    comment: "Error copy — 403 title"
                ),
                body: NSLocalizedString(
                    "error.forbidden.body",
                    value: "You don't have permission to do this. Contact your administrator if you need access.",
                    comment: "Error copy — 403 body"
                ),
                retryLabel: nil
            )

        case .notFound:
            return Copy(
                title: NSLocalizedString(
                    "error.notFound.title",
                    value: "Not Found",
                    comment: "Error copy — 404 title"
                ),
                body: NSLocalizedString(
                    "error.notFound.body",
                    value: "This item no longer exists or was moved. Return to the list and try again.",
                    comment: "Error copy — 404 body"
                ),
                retryLabel: nil
            )

        case .offline:
            return Copy(
                title: NSLocalizedString(
                    "error.offline.title",
                    value: "You're Offline",
                    comment: "Error copy — offline title"
                ),
                body: NSLocalizedString(
                    "error.offline.body",
                    value: "No internet connection detected. Connect to Wi-Fi or cellular to continue.",
                    comment: "Error copy — offline body"
                ),
                retryLabel: NSLocalizedString(
                    "error.offline.retry",
                    value: "Try Again",
                    comment: "Error copy — offline retry button"
                )
            )

        case .validation(let fields):
            let body: String
            if fields.isEmpty {
                body = NSLocalizedString(
                    "error.validation.body.generic",
                    value: "Fix all form inputs and try again.",
                    comment: "Error copy — validation body without field names"
                )
            } else {
                let listed = fields.prefix(3).joined(separator: ", ")
                let format = NSLocalizedString(
                    "error.validation.body.fields",
                    value: "Fix: %@.",
                    comment: "Error copy — validation body with field names (%@ = comma-joined field names)"
                )
                body = String(format: format, listed)
            }
            return Copy(
                title: NSLocalizedString(
                    "error.validation.title",
                    value: "Check Your Input",
                    comment: "Error copy — validation title"
                ),
                body: body,
                retryLabel: nil
            )

        case .rateLimited(let retrySeconds):
            let body: String
            if let seconds = retrySeconds {
                let format = NSLocalizedString(
                    "error.rateLimited.body.timed",
                    value: "Too many requests. Wait %d second(s) before trying again.",
                    comment: "Error copy — rate-limited body with retry delay (%d = seconds)"
                )
                body = String(format: format, seconds)
            } else {
                body = NSLocalizedString(
                    "error.rateLimited.body.generic",
                    value: "Too many requests. Wait a moment before trying again.",
                    comment: "Error copy — rate-limited body without retry delay"
                )
            }
            return Copy(
                title: NSLocalizedString(
                    "error.rateLimited.title",
                    value: "Too Many Requests",
                    comment: "Error copy — rate-limited title"
                ),
                body: body,
                retryLabel: NSLocalizedString(
                    "error.rateLimited.retry",
                    value: "Try Again",
                    comment: "Error copy — rate-limited retry button"
                )
            )

        case .unknown:
            return Copy(
                title: NSLocalizedString(
                    "error.unknown.title",
                    value: "Unexpected Error",
                    comment: "Error copy — unknown error title"
                ),
                body: NSLocalizedString(
                    "error.unknown.body",
                    value: "An unexpected error occurred. If this keeps happening, contact support.",
                    comment: "Error copy — unknown error body"
                ),
                retryLabel: NSLocalizedString(
                    "error.unknown.retry",
                    value: "Try Again",
                    comment: "Error copy — unknown error retry button"
                )
            )
        }
    }
}
