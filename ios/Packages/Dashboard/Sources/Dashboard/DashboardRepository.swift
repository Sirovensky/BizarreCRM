import Foundation
import Networking

public protocol DashboardRepository: Sendable {
    func load() async throws -> DashboardSnapshot
}

public struct DashboardSnapshot: Sendable {
    public let summary: DashboardSummary
    public let attention: NeedsAttention
}

public actor DashboardRepositoryImpl: DashboardRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async throws -> DashboardSnapshot {
        // Parallel fetch — Android does the same. Either can silently degrade
        // on the VM side if one fails; for MVP we fail the whole load.
        async let summary = api.dashboardSummary()
        async let attention = api.needsAttention()
        return try await DashboardSnapshot(summary: summary, attention: attention)
    }
}
