import Foundation
import Core
import Networking

// MARK: - Protocol

/// All WebAuthn/Passkey network operations.
/// Injected into ViewModels; concrete impl talks to APIClient.
/// Testable via MockPasskeyRepository in tests.
public protocol PasskeyRepository: Sendable {
    func beginRegistration(username: String) async throws -> PasskeyChallenge
    func completeRegistration(
        credentialId: String,
        attestationObject: String,
        clientDataJSON: String,
        nickname: String
    ) async throws -> PasskeyCredential

    func beginAuthentication(username: String?) async throws -> PasskeyChallenge
    func completeAuthentication(
        credentialId: String,
        authenticatorData: String,
        clientDataJSON: String,
        signature: String,
        userHandle: String?
    ) async throws -> PasskeyAuthToken

    func listCredentials() async throws -> [PasskeyCredential]
    func deleteCredential(id: String) async throws
}

// MARK: - Live Implementation

/// Actor wrapping the 6 WebAuthn endpoints.
/// Owns all APIClient calls so no ViewModel touches the network layer directly.
public actor LivePasskeyRepository: PasskeyRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func beginRegistration(username: String) async throws -> PasskeyChallenge {
        do {
            return try await api.webAuthnRegisterBegin(username: username)
        } catch {
            throw AppError.from(error)
        }
    }

    public func completeRegistration(
        credentialId: String,
        attestationObject: String,
        clientDataJSON: String,
        nickname: String
    ) async throws -> PasskeyCredential {
        do {
            return try await api.webAuthnRegisterComplete(
                credentialId: credentialId,
                attestationObject: attestationObject,
                clientDataJSON: clientDataJSON,
                nickname: nickname
            )
        } catch {
            throw AppError.from(error)
        }
    }

    public func beginAuthentication(username: String?) async throws -> PasskeyChallenge {
        do {
            return try await api.webAuthnAuthenticateBegin(username: username)
        } catch {
            throw AppError.from(error)
        }
    }

    public func completeAuthentication(
        credentialId: String,
        authenticatorData: String,
        clientDataJSON: String,
        signature: String,
        userHandle: String?
    ) async throws -> PasskeyAuthToken {
        do {
            return try await api.webAuthnAuthenticateComplete(
                credentialId: credentialId,
                authenticatorData: authenticatorData,
                clientDataJSON: clientDataJSON,
                signature: signature,
                userHandle: userHandle
            )
        } catch {
            throw AppError.from(error)
        }
    }

    public func listCredentials() async throws -> [PasskeyCredential] {
        do {
            return try await api.webAuthnListCredentials()
        } catch {
            throw AppError.from(error)
        }
    }

    public func deleteCredential(id: String) async throws {
        do {
            try await api.webAuthnDeleteCredential(id: id)
        } catch {
            throw AppError.from(error)
        }
    }
}
