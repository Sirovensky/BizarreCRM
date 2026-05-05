#if canImport(AuthenticationServices)
import Foundation
import Observation
import Core

// MARK: - State Machine

/// Exhaustive state enum for the Passkey flow.
/// `.done` carries the auth token so callers can complete the session.
public enum PasskeyState: Sendable, Equatable {
    case idle
    case challenging      // fetching challenge from server
    case waitingForOS     // OS sheet is visible (biometric / passkey selection)
    case verifying        // submitting assertion / attestation to server
    case done(token: String)
    case failed(AppError)

    public static func == (lhs: PasskeyState, rhs: PasskeyState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.challenging, .challenging),
             (.waitingForOS, .waitingForOS),
             (.verifying, .verifying):
            return true
        case (.done(let a), .done(let b)):
            return a == b
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - ViewModel

/// @Observable @MainActor ViewModel driving all Passkey UX.
/// Owns the PasskeyManager (OS sheet) and PasskeyRepository (network).
@Observable
@MainActor
public final class PasskeyViewModel {
    // MARK: Published State
    public private(set) var state: PasskeyState = .idle
    public private(set) var credentials: [PasskeyCredential] = []
    public private(set) var isLoadingCredentials: Bool = false

    // MARK: Dependencies
    private let manager: PasskeyManager
    private let repository: PasskeyRepository

    public init(manager: PasskeyManager, repository: PasskeyRepository) {
        self.manager = manager
        self.repository = repository
    }

    // MARK: - Sign-In Flow

    /// Full authentication ceremony:
    /// 1. authenticate/begin → challenge
    /// 2. OS sheet (PasskeyManager)
    /// 3. authenticate/complete → token
    ///
    /// On success: state transitions to `.done(token:)`.
    /// On cancellation: silently returns to `.idle`.
    public func signIn(username: String?) async {
        guard case .idle = state else { return }
        await runFlow {
            self.state = .challenging
            let challenge = try await self.repository.beginAuthentication(username: username)
            guard let challengeData = Data(base64Encoded: challenge.challenge.paddedBase64) else {
                throw AppError.envelope(reason: "Invalid challenge encoding from server")
            }

            self.state = .waitingForOS
            let result = try await self.manager.signInWithPasskey(
                username: username,
                challenge: challengeData
            )

            self.state = .verifying
            let token = try await self.repository.completeAuthentication(
                credentialId: result.credentialId.base64URLEncoded,
                authenticatorData: result.assertion.base64URLEncoded,
                clientDataJSON: result.clientDataJSON.base64URLEncoded,
                signature: result.assertion.base64URLEncoded,
                userHandle: result.userId.base64URLEncoded
            )
            self.state = .done(token: token.token)
        }
    }

    // MARK: - Registration Flow

    /// Full registration ceremony with a user-chosen nickname:
    /// 1. register/begin → challenge
    /// 2. OS sheet
    /// 3. register/complete → new PasskeyCredential
    public func register(username: String, displayName: String, nickname: String) async {
        guard case .idle = state else { return }
        await runFlow {
            self.state = .challenging
            let challenge = try await self.repository.beginRegistration(username: username)

            guard
                let challengeData = Data(base64Encoded: challenge.challenge.paddedBase64),
                let userIdData = (challenge.userId ?? "").data(using: .utf8)
            else {
                throw AppError.envelope(reason: "Invalid registration challenge from server")
            }

            self.state = .waitingForOS
            let registration = try await self.manager.registerPasskey(
                username: username,
                displayName: displayName,
                challenge: challengeData,
                userId: userIdData
            )

            self.state = .verifying
            let credential = try await self.repository.completeRegistration(
                credentialId: registration.credentialId.base64URLEncoded,
                attestationObject: registration.attestation.base64URLEncoded,
                clientDataJSON: registration.clientDataJSON.base64URLEncoded,
                nickname: nickname
            )

            // Refresh list and signal done (no auth token on registration).
            self.credentials = (self.credentials + [credential]).sorted {
                $0.createdAt > $1.createdAt
            }
            self.state = .done(token: "")
        }
    }

    // MARK: - Credential Management

    /// Loads all enrolled passkeys from the server.
    public func loadCredentials() async {
        isLoadingCredentials = true
        defer { isLoadingCredentials = false }
        do {
            let list = try await repository.listCredentials()
            credentials = list.sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Non-fatal: list may be unavailable during session boot.
            state = .failed(AppError.from(error))
        }
    }

    /// Deletes a credential and removes it from the local list.
    public func deleteCredential(id: String) async {
        do {
            try await repository.deleteCredential(id: id)
            credentials = credentials.filter { $0.id != id }
        } catch {
            state = .failed(AppError.from(error))
        }
    }

    /// Resets state back to `.idle` so the user can retry.
    public func reset() {
        state = .idle
    }

    // MARK: - Private helpers

    private func runFlow(operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
        } catch let appErr as AppError {
            if case .cancelled = appErr {
                state = .idle
            } else {
                state = .failed(appErr)
            }
        } catch {
            state = .failed(.from(error))
        }
    }
}

// MARK: - String helpers for base64url

private extension String {
    /// Pad a base64url string to a multiple of 4 so Data(base64Encoded:) accepts it.
    var paddedBase64: String {
        let urlDecoded = replacingOccurrences(of: "-", with: "+")
                            .replacingOccurrences(of: "_", with: "/")
        let rem = urlDecoded.count % 4
        return rem == 0 ? urlDecoded : urlDecoded + String(repeating: "=", count: 4 - rem)
    }
}
#endif
