import Foundation

// MARK: - Public Data Models

public struct PasskeyCredential: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let nickname: String
    public let createdAt: Date
    public let lastUsedAt: Date?
    public let deviceType: String?  // "iPhone" / "Mac" / ...

    public init(
        id: String,
        nickname: String,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        deviceType: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.deviceType = deviceType
    }
}

public struct PasskeyRegistration: Sendable {
    public let credentialId: Data
    public let attestation: Data
    public let clientDataJSON: Data

    public init(credentialId: Data, attestation: Data, clientDataJSON: Data) {
        self.credentialId = credentialId
        self.attestation = attestation
        self.clientDataJSON = clientDataJSON
    }
}

public struct PasskeySignInResult: Sendable {
    public let credentialId: Data
    public let assertion: Data
    public let userId: Data
    public let clientDataJSON: Data

    public init(credentialId: Data, assertion: Data, userId: Data, clientDataJSON: Data) {
        self.credentialId = credentialId
        self.assertion = assertion
        self.userId = userId
        self.clientDataJSON = clientDataJSON
    }
}

// MARK: - Server DTOs (WebAuthn endpoints)

/// Server response for register/begin and authenticate/begin.
public struct PasskeyChallenge: Decodable, Sendable {
    public let challenge: String   // base64url
    public let rpId: String?
    public let userId: String?     // base64url user handle (registration only)
    public let timeout: Int?
    public let userDisplayName: String?
}

/// Body for register/complete
struct PasskeyRegistrationComplete: Encodable, Sendable {
    let credentialId: String     // base64url
    let attestationObject: String // base64url
    let clientDataJSON: String    // base64url
    let nickname: String
}

/// Body for authenticate/complete
struct PasskeyAuthenticationComplete: Encodable, Sendable {
    let credentialId: String
    let authenticatorData: String  // base64url
    let clientDataJSON: String     // base64url
    let signature: String          // base64url
    let userHandle: String?        // base64url
}

/// Server auth response after successful assertion
public struct PasskeyAuthToken: Decodable, Sendable {
    public let token: String
    public let refreshToken: String?
    public let userId: String?
}
