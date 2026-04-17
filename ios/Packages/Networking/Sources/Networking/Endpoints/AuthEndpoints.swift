import Foundation

public struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct LoginResponse: Decodable, Sendable {
    public let requires2fa: Bool
    public let challenge: String?
    public let accessToken: String?
    public let refreshToken: String?
    public let expiresAt: Date?
}

public struct Verify2FARequest: Encodable, Sendable {
    public let challenge: String
    public let code: String

    public init(challenge: String, code: String) {
        self.challenge = challenge
        self.code = code
    }
}

public struct TokenPair: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
}

public struct DeviceTokenRegistration: Encodable, Sendable {
    public let token: String
    public let platform: String

    public init(token: String) {
        self.token = token
        self.platform = "ios"
    }
}
