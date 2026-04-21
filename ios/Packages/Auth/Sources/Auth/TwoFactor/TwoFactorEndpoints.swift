import Foundation
import Networking
import Core

// MARK: - Request / Response shapes
// All paths are under the router prefix /api/v1/auth/...
// Real endpoints: /account/2fa/disable (P2FA3 in auth.routes.ts).
// Stubbed endpoints: enroll, verify, status, recovery-codes, verify-recovery.

// MARK: Enroll

public struct TwoFactorEnrollRequest: Encodable, Sendable {}

public struct TwoFactorEnrollResponse: Decodable, Sendable {
    public let secret: String
    public let otpauthURI: String
    public let backupCodes: [String]
}

// MARK: Verify (confirm first-time enrollment)

public struct TwoFactorVerifyRequest: Encodable, Sendable {
    public let code: String
}

public struct TwoFactorVerifyResponse: Decodable, Sendable {
    public let verified: Bool
}

// MARK: Challenge (post-login 2FA gate)

public struct TwoFactorChallengeRequest: Encodable, Sendable {
    public let challengeToken: String
    public let code: String
}

public struct TwoFactorChallengeResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
}

// MARK: Disable

public struct TwoFactorDisableRequest: Encodable, Sendable {
    public let currentPassword: String
    public let totpCode: String
}

public struct TwoFactorDisableResponse: Decodable, Sendable {
    public let message: String?
}

// MARK: Regenerate recovery codes

public struct TwoFactorRegenerateCodesRequest: Encodable, Sendable {
    public let totpCode: String
}

public struct TwoFactorRegenerateCodesResponse: Decodable, Sendable {
    public let backupCodes: [String]
}

// MARK: Verify recovery code

public struct TwoFactorVerifyRecoveryRequest: Encodable, Sendable {
    public let code: String
}

public struct TwoFactorVerifyRecoveryResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let codesRemaining: Int?
}

// MARK: Status

public struct TwoFactorStatusResponse: Decodable, Sendable {
    public let enabled: Bool
    public let codesRemaining: Int?
}

// MARK: - APIClient extension

public extension APIClient {

    /// POST /api/v1/auth/2fa/enroll — returns TOTP secret + QR URI + backup codes.
    /// Stubbed: server endpoint not yet deployed.
    func twoFactorEnroll() async throws -> TwoFactorEnrollResponse {
        try await post(
            "/api/v1/auth/2fa/enroll",
            body: TwoFactorEnrollRequest(),
            as: TwoFactorEnrollResponse.self
        )
    }

    /// POST /api/v1/auth/2fa/verify — confirm initial TOTP code.
    /// Stubbed: server endpoint not yet deployed.
    func twoFactorVerify(code: String) async throws -> TwoFactorVerifyResponse {
        try await post(
            "/api/v1/auth/2fa/verify",
            body: TwoFactorVerifyRequest(code: code),
            as: TwoFactorVerifyResponse.self
        )
    }

    /// POST /api/v1/auth/2fa/challenge — submit 6-digit code at login gate.
    /// Stubbed: server uses /login/2fa-verify; challenge path reserved for settings flow.
    func twoFactorChallenge(challengeToken: String, code: String) async throws -> TwoFactorChallengeResponse {
        try await post(
            "/api/v1/auth/2fa/challenge",
            body: TwoFactorChallengeRequest(challengeToken: challengeToken, code: code),
            as: TwoFactorChallengeResponse.self
        )
    }

    /// POST /api/v1/auth/account/2fa/disable — disable 2FA (server endpoint exists: P2FA3).
    func twoFactorDisable(currentPassword: String, totpCode: String) async throws -> TwoFactorDisableResponse {
        try await post(
            "/api/v1/auth/account/2fa/disable",
            body: TwoFactorDisableRequest(currentPassword: currentPassword, totpCode: totpCode),
            as: TwoFactorDisableResponse.self
        )
    }

    /// POST /api/v1/auth/2fa/recovery-codes — regenerate backup codes.
    /// Stubbed: server endpoint not yet deployed.
    func twoFactorRegenerateCodes(totpCode: String) async throws -> TwoFactorRegenerateCodesResponse {
        try await post(
            "/api/v1/auth/2fa/recovery-codes",
            body: TwoFactorRegenerateCodesRequest(totpCode: totpCode),
            as: TwoFactorRegenerateCodesResponse.self
        )
    }

    /// POST /api/v1/auth/2fa/verify-recovery — consume a one-time recovery code.
    /// Stubbed: server endpoint not yet deployed.
    func twoFactorVerifyRecovery(code: String) async throws -> TwoFactorVerifyRecoveryResponse {
        try await post(
            "/api/v1/auth/2fa/verify-recovery",
            body: TwoFactorVerifyRecoveryRequest(code: code),
            as: TwoFactorVerifyRecoveryResponse.self
        )
    }

    /// GET /api/v1/auth/2fa/status — current 2FA enrollment state.
    /// Stubbed: server endpoint not yet deployed.
    func twoFactorStatus() async throws -> TwoFactorStatusResponse {
        try await get(
            "/api/v1/auth/2fa/status",
            query: nil,
            as: TwoFactorStatusResponse.self
        )
    }
}
