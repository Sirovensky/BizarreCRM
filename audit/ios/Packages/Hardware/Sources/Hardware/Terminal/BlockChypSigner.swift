import Foundation
import CryptoKit
import Core

// §17.3 BlockChyp request signing — Phase 5
//
// BlockChyp REST API authentication spec:
//   https://docs.blockchyp.com/rest-api/authentication
//
// Every request must carry four headers:
//   Nonce          — random hex string (≥32 hex chars)
//   Timestamp      — ISO-8601 UTC, e.g. "2006-01-02T15:04:05Z"
//   Authorization  — "Dual <apiKey>:<bearerToken>"
//   Signature      — HMAC-SHA256 of "<apiKey><bearerToken><timestamp><nonce><bodyHex>"
//                    encoded as lowercase hex.
//
// "bodyHex" is the lowercase hex encoding of the raw request body bytes.
// An empty body contributes an empty string (not "null" or "{}").

// MARK: - BlockChypSigner

/// Pure stateless signing helper for BlockChyp REST API requests.
/// All methods are static; no instance state.
public enum BlockChypSigner {

    // MARK: - Public API

    /// Compute the HMAC-SHA256 signature for a BlockChyp request.
    ///
    /// - Parameters:
    ///   - body:       Raw request body bytes (empty `Data()` for GET / bodyless requests).
    ///   - nonce:      Random nonce string (≥32 hex chars; callers use `randomNonce()`).
    ///   - timestamp:  Request timestamp (formatted as ISO-8601 UTC with no milliseconds).
    ///   - apiKey:     BlockChyp API key.
    ///   - bearerToken: BlockChyp bearer token.
    ///   - signingKey: BlockChyp signing key (HMAC secret, hex-encoded).
    /// - Returns: Lowercase hex HMAC-SHA256 signature string.
    public static func sign(
        body: Data,
        nonce: String,
        timestamp: Date,
        apiKey: String,
        bearerToken: String,
        signingKey: String
    ) -> String {
        let ts = Self.formatTimestamp(timestamp)
        let bodyHex = body.map { String(format: "%02x", $0) }.joined()
        let message = apiKey + bearerToken + ts + nonce + bodyHex
        let keyBytes = hexToData(signingKey) ?? Data(signingKey.utf8)
        let key = SymmetricKey(data: keyBytes)
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    /// Build the four required BlockChyp authentication headers for a request.
    ///
    /// - Parameters:
    ///   - credentials: BlockChyp API credentials.
    ///   - body:        Request body (empty `Data()` for bodyless requests).
    ///   - timestamp:   Defaults to `Date.now`; override in tests for determinism.
    ///   - nonce:       Defaults to a fresh random nonce; override in tests.
    /// - Returns: Dictionary of header key → value ready to merge into `URLRequest.allHTTPHeaderFields`.
    public static func authHeaders(
        credentials: BlockChypCredentials,
        body: Data,
        timestamp: Date = .now,
        nonce: String? = nil
    ) -> [String: String] {
        let n = nonce ?? randomNonce()
        let ts = formatTimestamp(timestamp)
        let sig = sign(
            body: body,
            nonce: n,
            timestamp: timestamp,
            apiKey: credentials.apiKey,
            bearerToken: credentials.bearerToken,
            signingKey: credentials.signingKey
        )
        return [
            "Nonce": n,
            "Timestamp": ts,
            "Authorization": "Dual \(credentials.apiKey):\(credentials.bearerToken)",
            "Signature": sig,
        ]
    }

    // MARK: - Helpers (internal for testing)

    /// Generate a cryptographically random 32-byte nonce encoded as lowercase hex (64 chars).
    public static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Format a `Date` as BlockChyp's required timestamp string: `"2006-01-02T15:04:05Z"`.
    /// Fractional seconds are truncated (BlockChyp rejects them).
    static func formatTimestamp(_ date: Date) -> String {
        Self.timestampFormatter.string(from: date)
    }

    // MARK: - Private

    // nonisolated(unsafe): formatter is created once with fixed options and never mutated.
    nonisolated(unsafe) private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")!
        return f
    }()

    /// Decode a lowercase/uppercase hex string to `Data`.
    /// Returns `nil` if the string contains non-hex characters or has odd length.
    static func hexToData(_ hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var result = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            result.append(byte)
            index = nextIndex
        }
        return result
    }
}
