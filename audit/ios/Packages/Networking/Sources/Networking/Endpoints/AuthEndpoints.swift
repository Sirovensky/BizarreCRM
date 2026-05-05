import Foundation

/// Request body for registering a device APNs token with the server.
/// The login DTOs (LoginReq / TwoFAReq / etc.) are inlined in `Auth/LoginFlow.swift`
/// because they're owned by the login flow; nothing else calls them.
public struct DeviceTokenRegistration: Encodable, Sendable {
    public let token: String
    public let platform: String

    public init(token: String) {
        self.token = token
        self.platform = "ios"
    }
}

/// Empty response wrapper for endpoints that just acknowledge success.
public struct LogoutResponse: Decodable, Sendable {
    public let message: String?
    public init(message: String? = nil) { self.message = message }
}

private struct EmptyLogoutBody: Encodable, Sendable { init() {} }

public extension APIClient {
    /// POST `/api/v1/auth/logout`. Asks the server to delete the current
    /// session row so a stolen access-token can't linger until its TTL.
    /// Caller should treat failures as non-fatal — local state still gets
    /// wiped on sign-out regardless of server reachability.
    func logout() async throws -> LogoutResponse {
        try await post("/api/v1/auth/logout",
                       body: EmptyLogoutBody(),
                       as: LogoutResponse.self)
    }
}
