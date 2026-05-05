import Foundation
import Networking
import Core

// MARK: - Request / Response shapes
// Endpoints under /api/v1/auth/magic-link/...
// Stubbed: server endpoints not yet deployed; shimmed per §74.3.

public struct MagicLinkRequestRequest: Encodable, Sendable {
    public let email: String
}

public struct MagicLinkRequestResponse: Decodable, Sendable {
    public let sent: Bool
}

public struct MagicLinkVerifyRequest: Encodable, Sendable {
    public let token: String
}

public struct MagicLinkVerifyResponse: Decodable, Sendable {
    public let authToken: String
}

// MARK: - APIClient extension

public extension APIClient {

    /// POST /api/v1/auth/magic-link/request — server sends a magic link email.
    /// Returns `{ sent: true }` on success. Stubbed: throws 501 when not deployed.
    func magicLinkRequest(email: String) async throws -> MagicLinkRequestResponse {
        try await post(
            "/api/v1/auth/magic-link/request",
            body: MagicLinkRequestRequest(email: email),
            as: MagicLinkRequestResponse.self
        )
    }

    /// POST /api/v1/auth/magic-link/verify — exchange one-time token for auth token.
    /// Stubbed: throws 501 when not deployed.
    func magicLinkVerify(token: String) async throws -> MagicLinkVerifyResponse {
        try await post(
            "/api/v1/auth/magic-link/verify",
            body: MagicLinkVerifyRequest(token: token),
            as: MagicLinkVerifyResponse.self
        )
    }
}
