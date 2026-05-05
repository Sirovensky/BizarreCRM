import Foundation
import Networking

// MARK: - Response types

public struct TrainingEnterResponse: Decodable, Sendable {
    public let demoTenantToken: String
    public let seededData: Bool
}

public struct TrainingResetResponse: Decodable, Sendable {
    public let ok: Bool
}

public struct TrainingStatusResponse: Decodable, Sendable {
    public let active: Bool
    public let tenantId: String
}

// MARK: - Empty body for POST with no params

struct EmptyBody: Encodable, Sendable {}

// MARK: - Endpoint helpers

public extension APIClient {
    /// POST /training/enter → demo tenant token
    func enterTrainingMode() async throws -> TrainingEnterResponse {
        try await post("training/enter", body: EmptyBody(), as: TrainingEnterResponse.self)
    }

    /// POST /training/reset-demo → reseeds demo data
    func resetDemoData() async throws -> TrainingResetResponse {
        try await post("training/reset-demo", body: EmptyBody(), as: TrainingResetResponse.self)
    }

    /// GET /training/status → active flag
    func trainingStatus() async throws -> TrainingStatusResponse {
        try await get("training/status", as: TrainingStatusResponse.self)
    }
}
