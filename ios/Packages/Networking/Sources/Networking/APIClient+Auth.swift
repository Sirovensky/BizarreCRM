import Foundation

// MARK: - Auth API extensions
//
// §2 Authentication — networking counterparts for the Auth package.
// Ground truth: packages/server/src/routes/auth.routes.ts
//
// Envelope: { success: Bool, data: T?, message: String? } — see APIResponse.swift.

// MARK: - /auth/setup-status (§2.1)

/// Response from GET /api/v1/auth/setup-status.
/// Controls whether to show the initial setup wizard or tenant picker.
public struct AuthSetupStatus: Decodable, Sendable {
    /// True when first-run setup has not been completed.
    public let needsSetup: Bool
    /// True when this server hosts multiple tenants.
    public let isMultiTenant: Bool

    public init(needsSetup: Bool, isMultiTenant: Bool) {
        self.needsSetup = needsSetup
        self.isMultiTenant = isMultiTenant
    }
}

// MARK: - /auth/me (§2.11)

/// Current authenticated user, returned by GET /api/v1/auth/me.
public struct AuthMe: Decodable, Sendable {
    public let id: Int
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let role: String
    public let tenantId: Int?

    public init(
        id: Int,
        username: String,
        email: String?,
        firstName: String?,
        lastName: String?,
        role: String,
        tenantId: Int?
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.tenantId = tenantId
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, role
        case firstName  = "first_name"
        case lastName   = "last_name"
        case tenantId   = "tenant_id"
    }
}

// MARK: - /auth/change-pin (§2.5)

/// Request body for POST /api/v1/auth/change-pin.
public struct ChangePinBody: Encodable, Sendable {
    public let currentPin: String
    public let newPin: String

    public init(currentPin: String, newPin: String) {
        self.currentPin = currentPin
        self.newPin = newPin
    }

    enum CodingKeys: String, CodingKey {
        case currentPin = "current_pin"
        case newPin     = "new_pin"
    }
}

// MARK: - /auth/change-password (§2.9)

/// Request body for POST /api/v1/auth/change-password.
public struct ChangePasswordBody: Encodable, Sendable {
    public let currentPassword: String
    public let newPassword: String

    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword     = "new_password"
    }
}

// MARK: - Generic success response

/// A minimal response for endpoints that only return `{ success, message }`.
public struct AuthAckResponse: Decodable, Sendable {
    public let message: String?
    public init(message: String? = nil) { self.message = message }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: §2.1 Setup-status probe

    /// GET /api/v1/auth/setup-status
    /// Called on first launch after the server URL is resolved to decide
    /// whether to show the initial setup wizard or tenant picker.
    func fetchAuthSetupStatus() async throws -> AuthSetupStatus {
        try await get("/api/v1/auth/setup-status", as: AuthSetupStatus.self)
    }

    // MARK: §2.11 Current user

    /// GET /api/v1/auth/me
    /// Validates the stored token and loads the current role/permissions.
    /// Call on cold start before rendering the main shell.
    func fetchMe() async throws -> AuthMe {
        try await get("/api/v1/auth/me", as: AuthMe.self)
    }

    // MARK: §2.5 Change PIN

    /// POST /api/v1/auth/change-pin
    func changePin(_ body: ChangePinBody) async throws -> AuthAckResponse {
        try await post("/api/v1/auth/change-pin", body: body, as: AuthAckResponse.self)
    }

    // MARK: §2.9 Change password

    /// POST /api/v1/auth/change-password
    func changePassword(_ body: ChangePasswordBody) async throws -> AuthAckResponse {
        try await post("/api/v1/auth/change-password", body: body, as: AuthAckResponse.self)
    }
}
