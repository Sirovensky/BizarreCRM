import Foundation

/// §2.11 refresh-and-retry. The `AuthSessionRefresher` is provided by the
/// `Auth` package at app launch (`Container+Registrations`) and injected
/// into `APIClientImpl.setRefresher(_:)`.
///
/// Contract:
/// - On a 401 for an authenticated request, APIClient calls
///   `refresher.refresh()`.
/// - Concrete implementation posts `/auth/refresh` with the current refresh
///   token (stored in `TokenStore`).
/// - On success the implementation MUST persist the new pair to
///   `TokenStore` AND return it so APIClient can update its local
///   `authToken`. APIClient then retries the original request ONCE.
/// - On failure it throws; APIClient posts `SessionEvents.sessionRevoked`
///   and surfaces the original 401.
///
/// Concurrent 401s are serialized inside APIClient via a single-flight
/// task gate.
public protocol AuthSessionRefresher: AnyObject, Sendable {
    func refresh() async throws -> (accessToken: String, refreshToken: String)
}
