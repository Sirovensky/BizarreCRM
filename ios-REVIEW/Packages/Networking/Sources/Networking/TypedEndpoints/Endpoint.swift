import Foundation

// MARK: - HTTPMethod

/// HTTP verbs used by the typed endpoint system.
/// Pure value type — no UIKit or feature-package imports.
public enum HTTPMethod: String, Sendable, Equatable {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

// MARK: - Endpoint protocol

/// A typed, value-type description of a single API route.
///
/// Conforming types carry the path, method, and optional query items
/// needed to construct a ``URLRequest``. They do **not** encode request
/// bodies — that remains the responsibility of the call site.
///
/// All server paths live under `/api/v1/`. Implementations must supply
/// the full path starting with `/api/v1/`.
public protocol Endpoint: Sendable {
    /// Full path relative to the server root, e.g. `/api/v1/tickets`.
    var path: String { get }

    /// HTTP method for this endpoint.
    var method: HTTPMethod { get }

    /// Optional query items appended to the URL.
    /// Returns `nil` (or an empty array) when no query string is needed.
    var queryItems: [URLQueryItem]? { get }
}

public extension Endpoint {
    /// Default: no query items.
    var queryItems: [URLQueryItem]? { nil }
}

// MARK: - URLRequest builder

public extension Endpoint {
    /// Constructs a ``URLRequest`` by appending ``path`` (and any ``queryItems``)
    /// to `baseURL`.
    ///
    /// - Parameter baseURL: The server root URL (e.g. `https://myshop.bizarrecrm.com`).
    ///   Must not contain a path component — any existing path is preserved but
    ///   `path` is appended verbatim.
    /// - Returns: A configured ``URLRequest`` ready for an ``URLSession`` call.
    /// - Throws: `EndpointError.invalidURL` when the resulting URL cannot be
    ///   constructed from the provided components.
    func build(baseURL: URL) throws -> URLRequest {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
            ?? URLComponents()
        components.path = path
        let items = queryItems?.filter { !($0.value?.isEmpty ?? true) }
        components.queryItems = (items?.isEmpty == false) ? items : nil

        guard let url = components.url else {
            throw EndpointError.invalidURL(path: path, base: baseURL.absoluteString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        return request
    }
}

// MARK: - EndpointError

/// Errors thrown by ``Endpoint/build(baseURL:)``.
public enum EndpointError: Error, Sendable, Equatable {
    /// The path + base URL combination could not form a valid `URL`.
    case invalidURL(path: String, base: String)
}
