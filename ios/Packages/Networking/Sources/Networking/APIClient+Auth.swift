import Foundation

// MARK: - APIClient+Auth
//
// Auth-domain endpoints for Agent 8 (Auth / Setup / Kiosk / Command Palette).
//
// Server routes grounded from packages/server/src/routes/auth.routes.ts:
//   GET  /api/v1/auth/me                        → { id, username, email, role, … }
//   POST /api/v1/auth/change-password           → { message }
//   POST /api/v1/auth/change-pin                → { message }
//   POST /api/v1/auth/setup                     → { accessToken?, user? }
//
// Envelope: { success: Bool, data: T?, message: String? }
// Change-password & change-PIN both return { success, message } with no data field.

// MARK: - Models

public struct MeResponse: Decodable, Sendable {
    public let id: Int64
    public let username: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let role: String
    public let tenantId: String?
    public let permissions: [String]?

    public init(
        id: Int64,
        username: String,
        email: String?,
        firstName: String?,
        lastName: String?,
        role: String,
        tenantId: String?,
        permissions: [String]?
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.role = role
        self.tenantId = tenantId
        self.permissions = permissions
    }

    enum CodingKeys: String, CodingKey {
        case id, username, email, role, permissions
        case firstName  = "first_name"
        case lastName   = "last_name"
        case tenantId   = "tenant_id"
    }
}

// MARK: - Change-password body / response

public struct ChangePasswordBody: Encodable, Sendable {
    public let currentPassword: String
    public let newPassword: String

    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }
}

public struct MessageOnlyResponse: Decodable, Sendable {
    public let message: String?
    public init(message: String?) { self.message = message }
}

// MARK: - Change-PIN body

public struct ChangePinBody: Encodable, Sendable {
    public let currentPin: String
    public let newPin: String

    public init(currentPin: String, newPin: String) {
        self.currentPin = currentPin
        self.newPin = newPin
    }
}

// MARK: - Signup body / response (§2.7)

/// POST /api/v1/auth/setup  — tenant creation (cloud signup).
/// Rate-limited 3/hour server-side.
public struct SignupSetupBody: Encodable, Sendable {
    public let username: String
    public let password: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let storeName: String?
    public let setupToken: String?

    public init(
        username: String,
        password: String,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        storeName: String? = nil,
        setupToken: String? = nil
    ) {
        self.username = username
        self.password = password
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.storeName = storeName
        self.setupToken = setupToken
    }

    enum CodingKeys: String, CodingKey {
        case username, password, email
        case firstName  = "first_name"
        case lastName   = "last_name"
        case storeName  = "store_name"
        case setupToken = "setup_token"
    }
}

public struct SignupSetupResponse: Decodable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let user: MeResponse?

    public init(accessToken: String?, refreshToken: String?, user: MeResponse?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: §2.11 — GET /auth/me

    /// Returns the currently-authenticated user's profile and role.
    /// Called on cold start to validate the stored token and populate `AppState`.
    func fetchMe() async throws -> MeResponse {
        try await get("/api/v1/auth/me", as: MeResponse.self)
    }

    // MARK: §2.9 — Change password

    /// POST /api/v1/auth/change-password
    func changePassword(_ body: ChangePasswordBody) async throws -> MessageOnlyResponse {
        try await post("/api/v1/auth/change-password", body: body, as: MessageOnlyResponse.self)
    }

    // MARK: §2.5 — Change PIN

    /// POST /api/v1/auth/change-pin
    func changePin(_ body: ChangePinBody) async throws -> MessageOnlyResponse {
        try await post("/api/v1/auth/change-pin", body: body, as: MessageOnlyResponse.self)
    }

    // MARK: §2.7 — Tenant signup

    /// POST /api/v1/auth/setup  — creates a new tenant + admin user.
    func signup(_ body: SignupSetupBody) async throws -> SignupSetupResponse {
        try await post("/api/v1/auth/setup", body: body, as: SignupSetupResponse.self)
    }
}
