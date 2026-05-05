import Foundation

public struct HealthStatus: Decodable, Sendable {
    public let ok: Bool
    public let version: String?
    public let uptimeSeconds: Double?
}

public extension APIClient {
    func health() async throws -> HealthStatus {
        try await get("/api/v1/health", as: HealthStatus.self)
    }
}
