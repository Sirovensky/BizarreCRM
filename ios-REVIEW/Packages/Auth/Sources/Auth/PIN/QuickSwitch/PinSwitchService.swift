import Foundation
import Networking
import Persistence

// MARK: - SwitchResult

/// Outcome of a PIN switch attempt.
public enum SwitchResult: Sendable {
    /// Switch succeeded; provides the new access token and user details.
    case success(accessToken: String, user: SwitchedUser)
    /// PIN did not match any roster entry or server rejected it.
    case wrongPin
    /// Account is temporarily locked until `until`.
    case locked(until: Date)
    /// Too many failures — full re-authentication required.
    case revoked
    /// Network or unexpected error.
    case networkError(Error)
}

// MARK: - PinSwitchService actor

/// Orchestrates the PIN Quick-Switch flow:
///
/// 1. Performs a local roster lookup to identify the candidate user for
///    client-side lockout gating.
/// 2. Calls `POST /api/v1/auth/switch-user` with the raw PIN.
/// 3. On server success: clears failure counter, upserts roster, stores the
///    new access token.
/// 4. On 401/403: bumps the failure counter and returns the resulting state.
///
/// The server is the authority on PIN validity. The local roster is used
/// only for avatar display and client-side lockout enforcement.
public actor PinSwitchService {

    // MARK: - Dependencies

    private let apiClient: APIClient
    private let roster: MultiUserRoster
    private let lockout: PinLockoutPolicy
    private let saveToken: @Sendable (String) async -> Void

    // MARK: - Init

    /// Designated initialiser used in production via DI / factory.
    /// - Parameters:
    ///   - apiClient:   Injected `APIClient` instance (owns base URL + auth headers).
    ///   - roster:      Multi-user keychain roster.
    ///   - lockout:     Lockout policy actor.
    ///   - saveToken:   Closure called with the new access token on success.
    ///                  Defaults to `TokenStore.shared.save(access:)` on the main actor.
    public init(
        apiClient: APIClient,
        roster: MultiUserRoster = .shared,
        lockout: PinLockoutPolicy = .shared,
        saveToken: @Sendable @escaping (String) async -> Void = { token in
            await MainActor.run {
                // Preserve the existing refresh token; only the access token
                // changes after a PIN switch. The refresh token arrives via
                // httpOnly cookie and is managed by the server/URLSession.
                let existing = TokenStore.shared.refreshToken ?? ""
                TokenStore.shared.save(access: token, refresh: existing)
            }
        }
    ) {
        self.apiClient = apiClient
        self.roster = roster
        self.lockout = lockout
        self.saveToken = saveToken
    }

    // MARK: - Public API

    /// Attempt to switch to the user whose PIN matches `pin`.
    ///
    /// - Parameters:
    ///   - pin:      Raw 4-6 digit PIN entered by the user.
    ///   - totpCode: Optional TOTP code for users with 2FA enabled.
    /// - Returns: A `SwitchResult` describing the outcome.
    public func attempt(pin: String, totpCode: String? = nil) async -> SwitchResult {
        // 1. Local roster lookup — identify candidate for lockout enforcement.
        let candidate = await roster.match(pin: pin)

        if let candidate {
            let state = await lockout.state(for: candidate.id)
            switch state {
            case .locked(let until): return .locked(until: until)
            case .revoked:           return .revoked
            case .allowed:           break
            }
        }

        // 2. Server call — authoritative PIN check.
        do {
            let data = try await apiClient.switchUser(pin: pin, totpCode: totpCode)
            let userId = data.user.id

            // 3. Success path — update local state.
            if candidate != nil {
                try? await lockout.recordSuccess(userId: userId)
            }
            // Upsert roster so avatar/name stay in sync with the server.
            try? await roster.upsert(user: data.user, pin: pin)
            // Persist new access token.
            await saveToken(data.accessToken)

            return .success(accessToken: data.accessToken, user: data.user)

        } catch {
            // 4. Failure path.
            let statusCode = (error as? APITransportError).flatMap {
                if case .httpStatus(let code, _) = $0 { return code }
                return nil
            }

            let isAuthFailure = statusCode == 401 || statusCode == 403

            if isAuthFailure, let candidate {
                let newState = (try? await lockout.recordFailure(userId: candidate.id)) ?? .allowed
                switch newState {
                case .locked(let until): return .locked(until: until)
                case .revoked:           return .revoked
                case .allowed:           return .wrongPin
                }
            }

            if isAuthFailure { return .wrongPin }
            return .networkError(error)
        }
    }
}
