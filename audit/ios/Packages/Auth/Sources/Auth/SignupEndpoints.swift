import Foundation
import Networking

// MARK: - §2.7 Signup / tenant creation endpoint

/// Shop type — drives defaults in the Setup Wizard (§36).
public enum ShopType: String, CaseIterable, Codable, Sendable {
    case repair     = "repair"
    case retail     = "retail"
    case hybrid     = "hybrid"
    case other      = "other"

    public var displayName: String {
        switch self {
        case .repair:  return "Repair shop"
        case .retail:  return "Retail store"
        case .hybrid:  return "Repair + retail"
        case .other:   return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .repair:  return "wrench.and.screwdriver"
        case .retail:  return "cart"
        case .hybrid:  return "building.2"
        case .other:   return "ellipsis.circle"
        }
    }
}

// MARK: - SignupRequest

/// Body for `POST /api/v1/auth/setup`.
/// Rate-limited to 3 requests per hour server-side.
public struct SignupRequest: Encodable, Sendable {
    public let username: String
    public let password: String
    public let email: String?
    public let firstName: String?
    public let lastName: String?
    public let storeName: String?
    public let shopType: ShopType?
    public let timezone: String?
    public let setupToken: String?

    public init(
        username: String,
        password: String,
        email: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        storeName: String? = nil,
        shopType: ShopType? = nil,
        timezone: String? = nil,
        setupToken: String? = nil
    ) {
        self.username = username
        self.password = password
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.storeName = storeName
        self.shopType = shopType
        self.timezone = timezone
        self.setupToken = setupToken
    }

    enum CodingKeys: String, CodingKey {
        case username
        case password
        case email
        case firstName    = "first_name"
        case lastName     = "last_name"
        case storeName    = "store_name"
        case shopType     = "shop_type"
        case timezone
        case setupToken   = "setup_token"
    }
}

// MARK: - SignupResponse

/// Response from `POST /api/v1/auth/setup`.
/// `accessToken` is present when the server supports auto-login
/// (root TODO `SIGNUP-AUTO-LOGIN-TOKENS`).
public struct SignupResponse: Decodable, Sendable {
    public let accessToken: String?
    public let refreshToken: String?
    public let message: String?

    public var autoLogin: Bool { accessToken != nil }

    public init(accessToken: String?, refreshToken: String?, message: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "accessToken"
        case refreshToken = "refreshToken"
        case message
    }
}

// MARK: - APIClient extension

public extension APIClient {

    /// POST `/api/v1/auth/setup`
    ///
    /// Creates a new tenant + owner account.
    /// Returns `SignupResponse` — check `.autoLogin` to determine whether
    /// to skip the login screen.
    func signup(request: SignupRequest) async throws -> SignupResponse {
        try await post(
            "/api/v1/auth/setup",
            body: request,
            as: SignupResponse.self
        )
    }
}
