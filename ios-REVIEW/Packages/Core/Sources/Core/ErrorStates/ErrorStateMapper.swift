import Foundation

// §63 — Maps concrete error types to `CoreErrorState` for UI consumption.
//
// Design notes:
//  - All mapping is pure / side-effect-free.
//  - Existing `AppError` cases are handled exhaustively; `@unknown default`
//    covers future additions added to `AppError` without a matching mapper
//    update.
//  - `URLError` mapping lives here rather than inside `CoreErrorState` to
//    keep the enum free of Foundation-level knowledge.

/// Maps `AppError`, `URLError`, or raw HTTP status codes to `CoreErrorState`.
public enum ErrorStateMapper {

    // MARK: — AppError

    /// Convert an `AppError` to the most appropriate `CoreErrorState`.
    public static func map(_ error: AppError) -> CoreErrorState {
        switch error {
        case .network:
            return .network
        case .server(let statusCode, let message):
            return .server(status: statusCode, message: message)
        case .envelope:
            return .server(status: 200, message: "The server response was malformed.")
        case .decoding:
            return .server(status: 200, message: "Could not read the server response.")
        case .unauthorized:
            return .unauthorized
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .conflict(let reason):
            return .server(status: 409, message: reason ?? "A conflict occurred.")
        case .rateLimited(let seconds):
            return .rateLimited(retrySeconds: seconds)
        case .validation(let fieldErrors):
            return .validation(Array(fieldErrors.keys))
        case .offline:
            return .offline
        case .syncDeadLetter(_, let reason):
            return .server(status: 0, message: reason)
        case .persistence:
            return .unknown
        case .keychain:
            return .unknown
        case .cancelled:
            return .unknown
        case .unknown:
            return .unknown
        }
    }

    // MARK: — URLError

    /// Convert a `URLError` to `CoreErrorState`.
    public static func map(_ error: URLError) -> CoreErrorState {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed:
            return .offline
        default:
            return .network
        }
    }

    // MARK: — Generic Error

    /// Convert any `Error` to `CoreErrorState`.
    ///
    /// Attempts `AppError` cast first, then `URLError`, then falls back to
    /// `.unknown`.
    public static func map(_ error: Error) -> CoreErrorState {
        if let appError = error as? AppError {
            return map(appError)
        }
        if let urlError = error as? URLError {
            return map(urlError)
        }
        // NSURLErrorDomain errors arrive as NSError
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let urlError = URLError(URLError.Code(rawValue: nsError.code))
            return map(urlError)
        }
        return .unknown
    }

    // MARK: — HTTP status code

    /// Derive a `CoreErrorState` directly from an HTTP status code and
    /// optional server message.
    public static func mapHTTP(
        statusCode: Int,
        message: String? = nil,
        retryAfterSeconds: Int? = nil
    ) -> CoreErrorState {
        switch statusCode {
        case 200...299:
            // Treat success codes as a programmer error — caller should not
            // be mapping a 2xx into an error state.
            return .unknown
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 422:
            return .validation(message.map { [$0] } ?? [])
        case 429:
            return .rateLimited(retrySeconds: retryAfterSeconds)
        case 500...599:
            return .server(status: statusCode, message: message)
        default:
            return .server(status: statusCode, message: message)
        }
    }
}
