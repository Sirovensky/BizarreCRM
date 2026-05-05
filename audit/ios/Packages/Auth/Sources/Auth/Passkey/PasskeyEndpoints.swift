import Foundation
import Networking

// MARK: - Request bodies (file-private so they don't leak into the module namespace)

private struct WebAuthnUsernameBody: Encodable, Sendable {
    let username: String
}

private struct WebAuthnOptionalUsernameBody: Encodable, Sendable {
    let username: String?
}

// MARK: - APIClient extension for WebAuthn endpoints
//
// All 6 routes live under /api/v1/auth/webauthn/.
// Per CLAUDE.md: base URL already includes /api/v1/, so we prepend that path.
// The server routes are defined in packages/server/src/routes/auth.routes.ts.

public extension APIClient {

    // MARK: Registration

    /// POST /auth/webauthn/register/begin
    /// Returns a FIDO2 challenge + relying-party info.
    func webAuthnRegisterBegin(username: String) async throws -> PasskeyChallenge {
        try await post(
            "/api/v1/auth/webauthn/register/begin",
            body: WebAuthnUsernameBody(username: username),
            as: PasskeyChallenge.self
        )
    }

    /// POST /auth/webauthn/register/complete
    /// Submits the attestation and persists the credential server-side.
    func webAuthnRegisterComplete(
        credentialId: String,
        attestationObject: String,
        clientDataJSON: String,
        nickname: String
    ) async throws -> PasskeyCredential {
        let body = PasskeyRegistrationComplete(
            credentialId: credentialId,
            attestationObject: attestationObject,
            clientDataJSON: clientDataJSON,
            nickname: nickname
        )
        return try await post(
            "/api/v1/auth/webauthn/register/complete",
            body: body,
            as: PasskeyCredential.self
        )
    }

    // MARK: Authentication

    /// POST /auth/webauthn/authenticate/begin
    /// Returns a FIDO2 assertion challenge. username is optional
    /// (pass nil for resident-key / discoverable-credential flow).
    func webAuthnAuthenticateBegin(username: String?) async throws -> PasskeyChallenge {
        try await post(
            "/api/v1/auth/webauthn/authenticate/begin",
            body: WebAuthnOptionalUsernameBody(username: username),
            as: PasskeyChallenge.self
        )
    }

    /// POST /auth/webauthn/authenticate/complete
    /// Submits the assertion signature; server returns an auth token on success.
    func webAuthnAuthenticateComplete(
        credentialId: String,
        authenticatorData: String,
        clientDataJSON: String,
        signature: String,
        userHandle: String?
    ) async throws -> PasskeyAuthToken {
        let body = PasskeyAuthenticationComplete(
            credentialId: credentialId,
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            signature: signature,
            userHandle: userHandle
        )
        return try await post(
            "/api/v1/auth/webauthn/authenticate/complete",
            body: body,
            as: PasskeyAuthToken.self
        )
    }

    // MARK: Credential Management

    /// GET /auth/webauthn/credentials
    /// Returns all passkeys enrolled for the current user.
    func webAuthnListCredentials() async throws -> [PasskeyCredential] {
        try await get(
            "/api/v1/auth/webauthn/credentials",
            as: [PasskeyCredential].self
        )
    }

    /// DELETE /auth/webauthn/credentials/:id
    /// Revokes a specific passkey credential.
    func webAuthnDeleteCredential(id: String) async throws {
        try await delete("/api/v1/auth/webauthn/credentials/\(id)")
    }
}
