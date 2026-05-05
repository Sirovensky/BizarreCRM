import Foundation

// §28.7 Logging redaction — Network inspector dev redactor
//
// In debug builds we emit URLRequest / URLResponse summaries to OSLog for
// diagnostics. The Authorization header is the highest-value secret on every
// API call (Bearer access token), so it must NEVER appear in plaintext in any
// log surface — including diagnostics bundles a user might attach to a bug
// report.
//
// `DebugNetworkLogRedactor` is the single, deterministic place where we strip
// `Authorization` (and related secret headers) before any log line is built.
// The redactor is pure / stateless — safe to call from any actor / task.
//
// ## Usage
// ```swift
// let safeHeaders = DebugNetworkLogRedactor.redact(headers: req.allHTTPHeaderFields ?? [:])
// AppLog.net.debug("→ \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "") headers=\(safeHeaders)")
// ```
//
// ## What gets redacted
//   - `Authorization`               → `Bearer <redacted-token len=N>`
//   - `Cookie`                      → `<redacted-cookie len=N>`
//   - `Set-Cookie`                  → `<redacted-set-cookie len=N>`
//   - `X-Api-Key`                   → `<redacted-api-key>`
//   - `X-BlockChyp-Auth`            → `<redacted-blockchyp-auth>`
//   - `Proxy-Authorization`         → `<redacted-proxy-auth>`
//
// Header-name comparison is case-insensitive (HTTP requirement; iOS canonicalizes
// these for us but third-party servers are sloppy).
public enum DebugNetworkLogRedactor {

    // MARK: - Configuration

    /// Lower-cased header names that must be redacted.
    private static let secretHeaderNames: Set<String> = [
        "authorization",
        "proxy-authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-blockchyp-auth",
        "x-blockchyp-bearer-token",
        "x-blockchyp-signature",
    ]

    // MARK: - Public API

    /// Returns a copy of `headers` with secret values replaced by length-only
    /// placeholders. Header names are preserved (in their original casing) so
    /// log readers can still see *that* an Authorization header was present —
    /// only the secret value is hidden.
    ///
    /// - Parameter headers: The raw headers as `[String: String]` (e.g. from
    ///   `URLRequest.allHTTPHeaderFields` or a flattened `URLResponse`).
    /// - Returns: A redacted copy. Original dictionary is unchanged.
    public static func redact(headers: [String: String]) -> [String: String] {
        var result = headers
        for (key, value) in headers {
            if secretHeaderNames.contains(key.lowercased()) {
                result[key] = redactValue(forHeader: key, value: value)
            }
        }
        return result
    }

    /// Redact a single header value. Exposed for callers that emit headers
    /// one-at-a-time (e.g. `URLResponse.allHeaderFields` iteration).
    public static func redactValue(forHeader name: String, value: String) -> String {
        let lower = name.lowercased()
        guard secretHeaderNames.contains(lower) else { return value }

        switch lower {
        case "authorization":
            // Preserve scheme ("Bearer", "Basic", "Digest") so debugging can
            // still distinguish auth modes; redact the credential payload.
            if let spaceIdx = value.firstIndex(of: " ") {
                let scheme = value[..<spaceIdx]
                let credentialLen = value.distance(from: value.index(after: spaceIdx), to: value.endIndex)
                return "\(scheme) <redacted-token len=\(credentialLen)>"
            }
            return "<redacted-authorization len=\(value.count)>"
        case "cookie":
            return "<redacted-cookie len=\(value.count)>"
        case "set-cookie":
            return "<redacted-set-cookie len=\(value.count)>"
        case "proxy-authorization":
            return "<redacted-proxy-auth>"
        default:
            return "<redacted-\(lower)>"
        }
    }

    /// Redact a URL's query string in case a tenant misuses `?token=…` or
    /// `?api_key=…` in dev. We never *send* secrets in query strings, but
    /// log lines should defend against future misuse.
    ///
    /// - Parameter url: The URL whose query may contain secret-shaped params.
    /// - Returns: A URL string with `token` / `access_token` / `api_key` /
    ///   `key` / `password` query values replaced by `<redacted>`.
    public static func redact(url: URL) -> String {
        guard
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let items = comps.queryItems,
            !items.isEmpty
        else { return url.absoluteString }

        let secretParams: Set<String> = [
            "token", "access_token", "refresh_token", "api_key", "apikey",
            "key", "password", "secret", "auth", "session",
        ]

        comps.queryItems = items.map { item in
            if secretParams.contains(item.name.lowercased()) {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return comps.url?.absoluteString ?? url.absoluteString
    }
}
