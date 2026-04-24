import Foundation

// §63 — Unified error state taxonomy for all UI layers.
// `CoreErrorState` is the single source of truth for what kind of error/empty
// condition a view is in. It is intentionally UI-level — it collapses the
// richer `AppError` domain model to the handful of distinct presentations the
// UI needs, discarding information that is only relevant for logging/recovery.

/// Unified error taxonomy for UI state presentation.
///
/// Use `ErrorStateMapper` to obtain a `CoreErrorState` from an `AppError`,
/// `URLError`, or raw HTTP status code.
public enum CoreErrorState: Sendable, Equatable {
    // MARK: — Transport

    /// TCP/TLS failure, DNS timeout, or other transport-layer problem.
    case network

    // MARK: — HTTP

    /// Non-2xx HTTP response with an associated status code and optional
    /// human-readable message from the server.
    case server(status: Int, message: String?)

    // MARK: — Auth / Authz

    /// HTTP 401 — token missing, invalid or expired.
    case unauthorized

    /// HTTP 403 — authenticated but the capability is not granted.
    case forbidden

    // MARK: — Resource

    /// HTTP 404 — the requested entity does not exist on the server.
    case notFound

    // MARK: — Connectivity

    /// Device has no network path.
    case offline

    // MARK: — Validation

    /// HTTP 422 / client-side form error.  Each element names a field that
    /// failed validation so the UI can highlight specific inputs.
    case validation([String])

    // MARK: — Rate limiting

    /// HTTP 429 — too many requests.  `retrySeconds` is the `Retry-After`
    /// value in seconds when the server provided one.
    case rateLimited(retrySeconds: Int?)

    // MARK: — Catch-all

    /// Any error that does not map to a more specific case.
    case unknown
}

// MARK: — Displayable metadata

extension CoreErrorState {
    /// SF Symbol name appropriate for this state.
    public var symbolName: String {
        switch self {
        case .network:             return "wifi.exclamationmark"
        case .server:              return "server.rack"
        case .unauthorized:        return "lock.fill"
        case .forbidden:           return "lock.slash.fill"
        case .notFound:            return "questionmark.folder"
        case .offline:             return "wifi.slash"
        case .validation:          return "exclamationmark.triangle.fill"
        case .rateLimited:         return "clock.badge.exclamationmark"
        case .unknown:             return "exclamationmark.circle"
        }
    }

    /// Short headline message suitable for display in a state view.
    public var title: String {
        switch self {
        case .network:             return "Connection Problem"
        case .server:              return "Server Error"
        case .unauthorized:        return "Session Expired"
        case .forbidden:           return "Access Denied"
        case .notFound:            return "Not Found"
        case .offline:             return "You're Offline"
        case .validation:          return "Check Your Input"
        case .rateLimited:         return "Too Many Requests"
        case .unknown:             return "Something Went Wrong"
        }
    }

    /// Longer description shown beneath the title.
    public var message: String {
        switch self {
        case .network:
            return "A network error occurred. Check your connection and try again."
        case .server(let status, let msg):
            return msg ?? "The server returned an unexpected error (HTTP \(status))."
        case .unauthorized:
            return "Your session has expired. Sign in again to continue."
        case .forbidden:
            return "You don't have permission to do this. Contact your administrator."
        case .notFound:
            return "The item you're looking for no longer exists."
        case .offline:
            return "You appear to be offline. Some features require a connection."
        case .validation(let fields):
            if fields.isEmpty {
                return "Please check the form for errors."
            }
            return "Please check the highlighted fields: \(fields.prefix(3).joined(separator: ", "))."
        case .rateLimited(let seconds):
            if let s = seconds {
                return "Too many requests. Try again in \(s) second\(s == 1 ? "" : "s")."
            }
            return "Too many requests. Please wait before trying again."
        case .unknown:
            return "An unexpected error occurred. If this persists, please contact support."
        }
    }

    /// Whether a primary action button is meaningful for this state.
    ///
    /// `.unauthorized` is included because it offers a "Sign In" CTA.
    public var isRetryable: Bool {
        switch self {
        case .network, .server, .offline, .rateLimited, .unknown, .unauthorized:
            return true
        case .forbidden, .notFound, .validation:
            return false
        }
    }

    /// Label for the primary action button, when present.
    public var retryLabel: String {
        switch self {
        case .unauthorized: return "Sign In"
        default:            return "Try Again"
        }
    }
}
