import Foundation

/// Mirrors the server's universal envelope: `{ success, data, error }`.
/// Same trap as the web codebase — payload lives directly in `.data`.
/// Unwrap once here, never at call sites.
public struct APIResponse<T: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let data: T?
    public let error: APIError?
}

public struct APIError: Decodable, Error, Sendable, LocalizedError {
    public let code: String
    public let message: String

    public var errorDescription: String? { message }
}

public enum APITransportError: Error, LocalizedError, Sendable {
    case invalidResponse
    case httpStatus(Int, body: String?)
    case decoding(String)
    case envelopeFailure(APIError?)
    case unauthorized
    case networkUnavailable
    case certificatePinFailed

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:      return "Invalid server response."
        case .httpStatus(let c, _): return "HTTP \(c)."
        case .decoding(let m):      return "Response decoding failed: \(m)"
        case .envelopeFailure(let e): return e?.message ?? "Request failed."
        case .unauthorized:         return "Session expired."
        case .networkUnavailable:   return "No internet connection."
        case .certificatePinFailed: return "Server certificate did not match the pinned key."
        }
    }
}
