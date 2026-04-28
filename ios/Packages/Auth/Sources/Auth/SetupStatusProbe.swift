import Foundation
import Networking
import Core

// MARK: - SetupStatusProbe
//
// §2.1 — Before rendering the login form, iOS hits GET /auth/setup-status to decide:
//   • needsSetup → push InitialSetupFlow
//   • isMultiTenant + no tenant chosen → push tenant picker
//   • else → render normal login
//
// The probe runs concurrently with showing the server-URL entry step so the
// ≤400ms budget is measured from the moment the user taps "Continue", not
// from app launch.
//
// Errors (server unreachable, 401, etc.) are surfaced via `ProbeResult.failure`
// and the login screen shows a retry CTA rather than blocking the user.

// MARK: - Response shape

public struct AuthSetupStatus: Decodable, Sendable {
    public let needsSetup: Bool
    public let isMultiTenant: Bool?

    public init(needsSetup: Bool, isMultiTenant: Bool?) {
        self.needsSetup = needsSetup
        self.isMultiTenant = isMultiTenant
    }
}

// MARK: - Result

public enum SetupProbeResult: Sendable {
    /// Server is reachable and returned setup status.
    case resolved(AuthSetupStatus)
    /// Network or server error; login screen should offer retry.
    case failure(String)
}

// MARK: - Actor

/// Stateless runner — one call per server URL change.
/// Inject via DI or call directly from `LoginFlow.submitServer()`.
public actor SetupStatusProbe {

    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// Hits `GET /api/v1/auth/setup-status` and returns the routing signal.
    ///
    /// The server must be reachable (base URL already set on `api`).
    /// Times out at 8s (matching the URLSession default minus headroom).
    public func run() async -> SetupProbeResult {
        do {
            let status = try await api.get("/api/v1/auth/setup-status", as: AuthSetupStatus.self)
            return .resolved(status)
        } catch APITransportError.httpStatus(let code, _) where code == 404 {
            // Older servers don't implement this endpoint; treat as no-setup-needed.
            return .resolved(AuthSetupStatus(needsSetup: false, isMultiTenant: nil))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - APIClient convenience

extension APIClient {
    /// GET /api/v1/auth/setup-status
    func fetchAuthSetupStatus() async throws -> AuthSetupStatus {
        try await get("/api/v1/auth/setup-status", as: AuthSetupStatus.self)
    }
}
