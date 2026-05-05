import Foundation
import Networking

// MARK: - Server connection test endpoints (§19.22)

private struct HealthWire: Decodable { let success: Bool }
private struct MeWire: Decodable { let success: Bool }

public extension APIClient {
    func healthPing() async throws -> Bool {
        let resp = try await get("/api/v1/health", as: HealthWire.self)
        return resp.success
    }

    func authMeCheck() async throws -> Bool {
        let resp = try await get("/api/v1/auth/me", as: MeWire.self)
        return resp.success
    }
}
