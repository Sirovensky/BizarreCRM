#if DEBUG
import Foundation

// §31 Test Fixtures Helpers — EnvelopeBuilder
// Constructs { success, data, message } JSON shells matching the BizarreCRM
// API contract (see ios/CLAUDE.md: "Envelope: { success: Bool, data: T?, message: String? }").

/// Builds JSON envelope payloads for use in HTTP stub responses.
///
/// The BizarreCRM API always wraps responses in a `{ success, data, message }` shell.
/// `EnvelopeBuilder` produces both typed Swift representations and raw `Data`/`String`
/// blobs suitable for injecting into URL loading stubs.
///
/// Usage:
/// ```swift
/// // Success with an encodable body
/// let data = try EnvelopeBuilder.success(data: customer)
///
/// // Success with a raw dictionary payload (no encoding step)
/// let data = EnvelopeBuilder.successRaw(data: ["id": 1, "name": "Alice"])
///
/// // Failure envelope
/// let data = EnvelopeBuilder.failure(message: "Not found")
/// ```
public enum EnvelopeBuilder {

    // MARK: — Errors

    public enum BuilderError: Error, CustomStringConvertible {
        case encodingFailed(underlying: Error)

        public var description: String {
            switch self {
            case let .encodingFailed(underlying):
                return "EnvelopeBuilder: failed to encode data payload. Underlying: \(underlying)"
            }
        }
    }

    // MARK: — Typed API (Encodable payload)

    /// Builds a `{ success: true, data: <encoded>, message: null }` envelope.
    ///
    /// - Parameters:
    ///   - payload: Any `Encodable` value to embed under the `data` key.
    ///   - encoder: Optional custom encoder (defaults to an `.iso8601` encoder).
    /// - Returns: Serialised `Data` of the full envelope JSON.
    public static func success<T: Encodable>(
        data payload: T,
        encoder: JSONEncoder? = nil
    ) throws -> Data {
        let enc = encoder ?? defaultEncoder()
        let payloadData: Data
        do {
            payloadData = try enc.encode(payload)
        } catch {
            throw BuilderError.encodingFailed(underlying: error)
        }
        // Deserialise payload back to Any so we can merge it into the envelope dict.
        let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
        let envelope: [String: Any] = [
            "success": true,
            "data": payloadObject,
            "message": NSNull()
        ]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    /// Builds a `{ success: true, data: null, message: null }` envelope with no body.
    public static func successEmpty() -> Data {
        let envelope: [String: Any] = [
            "success": true,
            "data": NSNull(),
            "message": NSNull()
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    // MARK: — Raw dictionary API (no Encodable step)

    /// Builds a success envelope where `data` is an arbitrary dictionary.
    ///
    /// Useful when you already have a `[String: Any]` from `FixtureLoader.loadRaw(_:)`.
    ///
    /// - Parameter payload: The dictionary to embed under `data`.
    /// - Returns: Serialised `Data` of the full envelope JSON.
    public static func successRaw(data payload: [String: Any]) -> Data {
        let envelope: [String: Any] = [
            "success": true,
            "data": payload,
            "message": NSNull()
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    /// Builds a success envelope where `data` is an array of dictionaries.
    public static func successRawArray(data payload: [[String: Any]]) -> Data {
        let envelope: [String: Any] = [
            "success": true,
            "data": payload,
            "message": NSNull()
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    // MARK: — Failure envelope

    /// Builds a `{ success: false, data: null, message: <msg> }` envelope.
    ///
    /// - Parameter message: Human-readable error message returned to the caller.
    public static func failure(message: String) -> Data {
        let envelope: [String: Any] = [
            "success": false,
            "data": NSNull(),
            "message": message
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    // MARK: — String convenience wrappers

    /// Same as `success(data:encoder:)` but returns a UTF-8 `String`.
    public static func successString<T: Encodable>(
        data payload: T,
        encoder: JSONEncoder? = nil
    ) throws -> String {
        let data = try success(data: payload, encoder: encoder)
        return String(decoding: data, as: UTF8.self)
    }

    /// Same as `failure(message:)` but returns a UTF-8 `String`.
    public static func failureString(message: String) -> String {
        String(decoding: failure(message: message), as: UTF8.self)
    }

    // MARK: — Private

    private static func defaultEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = .sortedKeys
        return enc
    }
}
#endif
