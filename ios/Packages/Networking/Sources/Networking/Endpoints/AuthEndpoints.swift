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
