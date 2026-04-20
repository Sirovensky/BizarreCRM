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
    }

    public func refresh() async throws -> (accessToken: String, refreshToken: String) {
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

        AppLog.auth.info("Session token refreshed successfully")
        return (accessToken: resp.accessToken, refreshToken: resp.refreshToken)
    }
}
