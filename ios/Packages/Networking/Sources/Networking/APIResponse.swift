import Foundation

/// Mirrors the server's universal envelope: `{ success, data, message }`.
/// Server-side definition:
///   `res.json({ success: true, data: { ... } })` or
///   `res.json({ success: false, message: "..." })`
///
/// Unwrap once here, never at call sites.
public struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let data: T?
    public let message: String?
}

public enum APITransportError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int, message: String?)
    case decoding(String)
    case envelopeFailure(message: String?)
    case unauthorized
    case networkUnavailable
    case certificatePinFailed
    case noBaseURL

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let code, let message):
            return message ?? "Request failed (\(code))."
        case .decoding(let detail):
            return "Could not read the server response: \(detail)"
        case .envelopeFailure(let message):
            return message ?? "Request failed."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .networkUnavailable:
            return "No internet connection."
        case .certificatePinFailed:
            return "The server's certificate did not match the pinned key."
        case .noBaseURL:
            return "No server selected — enter your server address."
        }
    }
}
