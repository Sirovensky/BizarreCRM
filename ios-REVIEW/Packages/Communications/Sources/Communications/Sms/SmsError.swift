import Foundation

// MARK: - SmsError

/// Domain error type for the SMS subsystem.
///
/// Wraps low-level failures (e.g. `DecodingError` from the conversations
/// endpoint) into user-readable strings so that ViewModels can surface them
/// without leaking implementation detail through the UI.
public enum SmsError: Error, LocalizedError, Sendable {

    /// The server response for an SMS conversation list could not be decoded.
    ///
    /// - Parameters:
    ///   - underlying: The original `DecodingError` (or other `Error`) that
    ///                 caused the failure.
    case decodingConversations(underlying: Error)

    /// The server response for an SMS thread could not be decoded.
    case decodingThread(underlying: Error)

    /// A conversation's `conv_phone` field was missing or empty.
    /// This is a server-contract violation — see §91.14 server-side audit note.
    case missingConvPhone

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .decodingConversations(let underlying):
            return friendlyDecodeMessage(underlying)
                ?? "Could not load conversations — unexpected server response."
        case .decodingThread(let underlying):
            return friendlyDecodeMessage(underlying)
                ?? "Could not load this thread — unexpected server response."
        case .missingConvPhone:
            return "A conversation from the server was missing a phone number and was skipped."
        }
    }

    // MARK: - Private helpers

    /// Converts a `DecodingError` into a user-friendly, non-technical string.
    /// Returns `nil` for non-`DecodingError` types so callers can supply their
    /// own fallback message.
    private func friendlyDecodeMessage(_ error: Error) -> String? {
        guard let decodingError = error as? DecodingError else { return nil }
        switch decodingError {
        case .keyNotFound(let key, _):
            return "The server response was missing the '\(key.stringValue)' field."
        case .typeMismatch(_, let context):
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Unexpected data type for '\(field)' in the server response."
        case .valueNotFound(_, let context):
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "The '\(field)' field was null in the server response."
        case .dataCorrupted(let context):
            // Avoid leaking raw data into user-facing strings.
            _ = context
            return "The server returned malformed data."
        @unknown default:
            return "Could not parse the server response."
        }
    }
}
