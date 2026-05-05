import Foundation

// §29.7 Networking — Request coalescing.
//
// Dedupes concurrent identical idempotent (GET) requests so N callers asking
// for the same resource at the same time only generate one network round-trip.
// All N callers `await` the same in-flight Task and receive the same value.
//
// Scope:
//   • Only safe for read-only operations whose response is shareable across
//     callers — i.e. GETs without per-caller side effects. Never use for
//     POST/PUT/PATCH/DELETE.
//   • Key includes HTTP method + absolute URL (incl. query) + Authorization
//     header digest, so requests with different bearers don't collapse into
//     a shared response (would leak data across tenants / users).
//
// Lifecycle:
//   • An in-flight task is removed from the map as soon as it completes
//     (success or failure). Subsequent calls re-fetch fresh.
//   • This is in-memory only and process-local. No persistence.
//
// Wired from APIClientImpl.get(...) — see APIClient.swift.

/// Type-erased Sendable wrapper. Required because Swift 6 forbids
/// `Task<Any, Error>` (Any is not Sendable). The wrapper carries an
/// arbitrary value across concurrency domains; the caller casts back
/// to the originally requested generic T.
public struct AnySendable: @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) { self.value = value }
}

public actor RequestCoalescer {

    public static let shared = RequestCoalescer()

    // Type-erased in-flight tasks keyed by request fingerprint.
    // Value is boxed because the caller decodes a generic T; the actor stores
    // one erased task per key and casts back to T for each waiter.
    private var inFlight: [String: Task<AnySendable, Error>] = [:]

    public init() {}

    /// Run `work` for `key`, sharing the resulting value with every other
    /// concurrent caller using the same key. The task is removed from the
    /// in-flight map as soon as the first attempt completes.
    public func run<T: Sendable>(
        key: String,
        work: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        if let existing = inFlight[key] {
            let boxed = try await existing.value
            guard let typed = boxed.value as? T else {
                throw CoalescerError.typeMismatch
            }
            return typed
        }
        let task = Task<AnySendable, Error> {
            AnySendable(try await work())
        }
        inFlight[key] = task
        defer { inFlight.removeValue(forKey: key) }
        let boxed = try await task.value
        guard let typed = boxed.value as? T else {
            throw CoalescerError.typeMismatch
        }
        return typed
    }

    /// Build the dedup key for an outgoing request. Include the absolute URL,
    /// the method, and a digest of the Authorization header so different
    /// users / tenants never share a response.
    public nonisolated static func key(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let authDigest: String
        if let auth = request.value(forHTTPHeaderField: "Authorization") {
            authDigest = String(auth.hashValue)
        } else {
            authDigest = "anon"
        }
        return "\(method) \(url) \(authDigest)"
    }
}

public enum CoalescerError: Error, Sendable {
    case typeMismatch
}
