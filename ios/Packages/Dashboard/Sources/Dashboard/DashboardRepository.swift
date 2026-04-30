import Foundation
import Networking

public protocol DashboardRepository: Sendable {
    func load() async throws -> DashboardSnapshot
}

/// §3.1 Full dashboard snapshot — summary KPIs + extended financial KPIs + needs-attention.
public struct DashboardSnapshot: Sendable {
    public let summary: DashboardSummary
    public let kpis: DashboardKPIs?   // nil when user lacks report access or call fails
    public let attention: NeedsAttention

    public init(summary: DashboardSummary, kpis: DashboardKPIs? = nil, attention: NeedsAttention) {
        self.summary = summary
        self.kpis = kpis
        self.attention = attention
    }
}

public actor DashboardRepositoryImpl: DashboardRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async throws -> DashboardSnapshot {
        // Parallel fetch — Android does the same. KPIs failure is non-fatal
        // (role-gated: cashiers/techs don't have report access); summary +
        // attention are required.
        async let summary = api.dashboardSummary()
        async let attention = api.needsAttention()
        let kpis = try? await api.dashboardKPIs()
        return try await DashboardSnapshot(summary: summary, kpis: kpis, attention: attention)
    }
}
