import Foundation

// §71 Privacy-first analytics — URLSession abstraction for testability

/// Minimal URLSession interface used by `TenantServerAnalyticsSink`.
/// Conform `URLSession` to this in production; use a stub in tests.
public protocol AnalyticsURLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AnalyticsURLSessionProtocol {}
