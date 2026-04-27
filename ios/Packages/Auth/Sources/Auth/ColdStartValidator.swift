import Foundation
import Networking
import Persistence
import Core

// MARK: - ColdStartValidator
//
// §2.11 — On cold start, validate the stored bearer token by calling
// GET /auth/me. Outcomes:
//   • Success  → populate role/permissions into callers; proceed to dashboard.
//   • 401/403  → token is stale; wipe and redirect to login (same as session revoke).
//   • Network  → token is assumed valid; proceed to dashboard with offline mode.
//
// Designed to be called once by the session bootstrapper immediately after
// the app finishes launching and a stored token is found.

// MARK: - Validation result

public enum ColdStartValidationResult: Sendable {
    /// Token is valid; caller receives current user profile.
    case valid(MeResponse)
    /// Token was rejected by the server (401/403). Local state wiped.
    case revoked
    /// Network was unreachable; optimistically proceed to dashboard.
    case offline
}

// MARK: - Validator actor

public actor ColdStartValidator {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Validates the stored auth token against GET /api/v1/auth/me.
    ///
    /// On `.revoked`, this method also clears the local token store so
    /// downstream callers don't need to handle that themselves.
    public func validate() async -> ColdStartValidationResult {
        guard TokenStore.shared.accessToken != nil else {
            // No token stored — caller should route to login directly.
            return .revoked
        }

        do {
            let me = try await api.fetchMe()
            return .valid(me)
        } catch APITransportError.httpStatus(let code, _) where code == 401 || code == 403 {
            await MainActor.run { TokenStore.shared.clear() }
            return .revoked
        } catch {
            // Network error / timeout — proceed optimistically
            AppLog.auth.warning("Cold-start /auth/me failed (offline?): \(error.localizedDescription, privacy: .public)")
            return .offline
        }
    }
}
