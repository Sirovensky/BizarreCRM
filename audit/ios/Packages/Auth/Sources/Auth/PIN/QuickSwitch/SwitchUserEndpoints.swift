import Foundation
import Networking

// MARK: - Request / Response models

/// Body for POST /auth/switch-user.
struct SwitchUserRequestBody: Encodable, Sendable {
    let pin: String
    let totpCode: String?

    enum CodingKeys: String, CodingKey {
        case pin
        case totpCode = "totpCode"
    }
}

/// User object returned inside `data` by POST /auth/switch-user.
public struct SwitchedUser: Decodable, Sendable, Identifiable {
    public let id: Int
    public let username: String
    public let email: String
    public let firstName: String
    public let lastName: String
    public let role: String
    public let avatarUrl: String?
    public let permissions: [String]?

    /// Memberwise initialiser — used in tests and local construction.
    public init(
        id: Int,
        username: String,
        email: String,
        firstName: String,
        lastName: String,
        role: String,
        avatarUrl: String?,
        permissions: [String]?
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.avatarUrl = avatarUrl
        self.permissions = permissions
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, role, permissions
        case firstName  = "first_name"
        case lastName   = "last_name"
        case avatarUrl  = "avatar_url"
    }

    public var displayName: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? username : full
    }
}

/// Wrapped `data` payload for POST /auth/switch-user.
public struct SwitchUserData: Decodable, Sendable {
    public let accessToken: String
    public let user: SwitchedUser

    public init(accessToken: String, user: SwitchedUser) {
        self.accessToken = accessToken
        self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "accessToken"
        case user
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// POST `/api/v1/auth/switch-user`
    ///
    /// Authenticates the supplied PIN against all active server users.
    /// On success returns a fresh access token + the matched user.
    /// The caller is responsible for storing the new token and updating
    /// the active-user context.
    ///
    /// - Parameters:
    ///   - pin: Raw 4-6 digit PIN string entered by the user.
    ///   - totpCode: Optional TOTP code, required when the matched user has 2FA enabled.
    func switchUser(pin: String, totpCode: String? = nil) async throws -> SwitchUserData {
        try await post(
            "/api/v1/auth/switch-user",
            body: SwitchUserRequestBody(pin: pin, totpCode: totpCode),
            as: SwitchUserData.self
        )
    }
}
