import Foundation

// §63 Error taxonomy — Phase 0 foundation
// All cases are `Sendable`-safe (no reference types in associated values that aren't Sendable).

public enum AppError: Error, Sendable {
    // MARK: — Transport
    /// TCP/TLS failure, timeout, no route to host.
    case network(underlying: URLError?)

    // MARK: — HTTP
    /// Non-2xx response whose status code isn't covered by a named case.
    case server(statusCode: Int, message: String?)
    /// Response had HTTP 200 but the `{ success, data, message }` envelope was malformed.
    case envelope(reason: String)
    /// JSON (or other) decoding failed.
    case decoding(type: String, underlying: Error?)

    // MARK: — Named HTTP codes
    /// 401 — token missing, invalid or expired.
    case unauthorized
    /// 403 — authenticated but the capability is not granted.
    case forbidden(capability: String?)
    /// 404 — entity not found on the server.
    case notFound(entity: String?)
    /// 409 — optimistic-concurrency conflict.
    case conflict(reason: String?)
    /// 429 — server asked us to back off.
    case rateLimited(retryAfterSeconds: Int?)
    /// 422 — one or more fields failed server-side validation.
    case validation(fieldErrors: [String: String])

    // MARK: — Connectivity
    /// Device has no network path (NWPathMonitor reported `.unsatisfied`).
    case offline

    // MARK: — Sync
    /// A sync operation exhausted all retries and was moved to the dead-letter queue.
    case syncDeadLetter(queueId: String, reason: String)

    // MARK: — Storage
    /// A GRDB / SQLCipher operation failed.
    case persistence(underlying: Error?)
    /// A Keychain SecItem* call returned a non-zero OSStatus.
    case keychain(status: Int32)

    // MARK: — Control flow
    /// The operation was cancelled by the user or by the system (e.g. task cancellation).
    case cancelled
    /// Anything that doesn't map to a named case.
    case unknown(underlying: Error?)
}

// MARK: — LocalizedError

extension AppError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .network:
            return "A network error occurred. Please check your connection."
        case .server(let code, let msg):
            return msg ?? "Server returned an unexpected error (HTTP \(code))."
        case .envelope(let reason):
            return "The server response was malformed: \(reason)."
        case .decoding(let type, _):
            return "Could not read the server response (\(type))."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .forbidden(let cap):
            if let cap { return "Your role doesn't allow \(cap). Ask an admin." }
            return "You don't have permission to do this."
        case .notFound(let entity):
            if let entity { return "\(entity) not found." }
            return "The requested item was not found."
        case .conflict(let reason):
            return reason ?? "A conflict occurred. The item may have been changed by someone else."
        case .rateLimited(let seconds):
            if let s = seconds { return "Too many requests. Try again in \(s) second\(s == 1 ? "" : "s")." }
            return "Too many requests. Please wait before trying again."
        case .validation(let errors):
            let summary = errors.values.prefix(2).joined(separator: "; ")
            return "Please check the highlighted fields: \(summary)."
        case .offline:
            return "You appear to be offline. Some features need a connection."
        case .syncDeadLetter(_, let reason):
            return "A background sync failed and was abandoned: \(reason)."
        case .persistence:
            return "A local storage error occurred. Try restarting the app."
        case .keychain(let status):
            return "A secure storage error occurred (status \(status))."
        case .cancelled:
            return "The operation was cancelled."
        case .unknown(let err):
            return err?.localizedDescription ?? "An unexpected error occurred."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .network, .offline:
            return "Check Wi-Fi or cellular connectivity, then retry."
        case .unauthorized:
            return "Sign in again to continue."
        case .forbidden:
            return "Contact your administrator to request access."
        case .rateLimited(let seconds):
            if let s = seconds { return "Wait \(s) second\(s == 1 ? "" : "s") before retrying." }
            return "Wait a moment before retrying."
        case .persistence:
            return "Restart the app. If this persists, contact support."
        case .conflict:
            return "Reload the latest version of the item and apply your changes again."
        default:
            return nil
        }
    }
}

// MARK: — Static factory helpers

extension AppError {
    /// Map any `Error` to the most specific `AppError` case.
    /// Existing `AppError` values pass through unchanged.
    public static func from(_ error: Error) -> AppError {
        if let appErr = error as? AppError { return appErr }
        if let urlErr = error as? URLError { return .network(underlying: urlErr) }
        if let decErr = error as? DecodingError {
            let typeName: String
            switch decErr {
            case .typeMismatch(let t, _): typeName = String(describing: t)
            case .valueNotFound(let t, _): typeName = String(describing: t)
            case .keyNotFound(let k, _): typeName = k.stringValue
            case .dataCorrupted: typeName = "DataCorrupted"
            @unknown default: typeName = "Unknown"
            }
            return .decoding(type: typeName, underlying: decErr)
        }
        if error is EncodingError { return .decoding(type: "Encoding", underlying: error) }
        if (error as NSError).domain == NSURLErrorDomain {
            let urlErr = URLError(URLError.Code(rawValue: (error as NSError).code))
            return .network(underlying: urlErr)
        }
        return .unknown(underlying: error)
    }

    /// Map an HTTP status code to the appropriate `AppError`.
    /// - Parameters:
    ///   - statusCode: The HTTP response status code.
    ///   - message:    Optional server-provided message string.
    ///   - retryAfter: Optional `Retry-After` header value in seconds (429 only).
    ///   - fieldErrors: Optional field→message map (422 only).
    public static func fromHttp(
        statusCode: Int,
        message: String? = nil,
        retryAfter: Int? = nil,
        fieldErrors: [String: String] = [:]
    ) -> AppError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden(capability: message)
        case 404: return .notFound(entity: message)
        case 409: return .conflict(reason: message)
        case 422: return .validation(fieldErrors: fieldErrors.isEmpty ? (message.map { ["_": $0] } ?? [:]) : fieldErrors)
        case 429: return .rateLimited(retryAfterSeconds: retryAfter)
        default:  return .server(statusCode: statusCode, message: message)
        }
    }
}
