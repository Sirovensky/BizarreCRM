import Foundation
import Core
import Networking
import Persistence

/// Concrete `AuthSessionRefresher` that services APIClient's 401
/// refresh-and-retry path (§2.11). Wired at app launch in
/// `AppServices` / Container registration, then injected into
/// APIClient via `APIClient.setRefresher(_:)`.
///
/// Contract (from protocol doc):
/// - Read the current refresh token from `TokenStore`.
/// - POST `/auth/refresh` with `{ refreshToken }`.
/// - On success, persist the returned pair to `TokenStore` and hand
///   them back. APIClient rotates its internal `authToken` and retries
///   the original request ONCE.
/// - On failure, throw — APIClient surfaces the original 401 and posts
///   `SessionEvents.sessionRevoked`.
public final class AuthRefresher: AuthSessionRefresher, @unchecked Sendable {

    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    private struct Req: Encodable, Sendable {
        let refreshToken: String
    }

    private struct Resp: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String
        /// §28.14 — Server may include `rotated: true` when the refresh token
        /// was rotated (i.e., the old token is now invalid). The client uses
        /// this flag to update `TokenStore` even if the access token is the same.
        /// Absent from older server builds; defaults to `false`.
        let rotated: Bool?
    }

    // MARK: - §28.14 Rotation flag

    /// `true` after the most recent successful refresh that carried a new
    /// refresh token from the server (`rotated == true`).  Reset to `false`
    /// on the next call to `refresh()`.
    ///
    /// Observers (e.g. `SessionTimer`) may use this to emit an audit event
    /// when rotation occurs, without needing to compare token strings.
    public private(set) var lastRefreshWasRotated: Bool = false

    public func refresh() async throws -> (accessToken: String, refreshToken: String) {
        lastRefreshWasRotated = false
        let stored = await MainActor.run { TokenStore.shared.refreshToken }
        guard let current = stored, !current.isEmpty else {
            AppLog.auth.warning("refresh() called with no stored refresh token")
            throw APITransportError.unauthorized
        }

        let resp = try await apiClient.post(
            "/auth/refresh",
            body: Req(refreshToken: current),
            as: Resp.self
        )

        // Persist new pair + update APIClient bearer.
        await MainActor.run {
            TokenStore.shared.save(access: resp.accessToken, refresh: resp.refreshToken)
        }
        await apiClient.setAuthToken(resp.accessToken)

        // §28.14 — record whether the server rotated the refresh token.
        lastRefreshWasRotated = resp.rotated ?? false
        if lastRefreshWasRotated {
            AppLog.auth.info("Session token refreshed + refresh token rotated")
        } else {
            AppLog.auth.info("Session token refreshed successfully")
        }
        return (accessToken: resp.accessToken, refreshToken: resp.refreshToken)
    }
}
