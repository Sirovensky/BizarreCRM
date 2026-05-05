import Foundation
import Networking

// MARK: - FinancialDashboardRepository
//
// Protocol + actor implementation for §59 Financial Dashboard.
//
// Calls: GET /api/v1/owner-pl/summary (ownerPl.routes.ts:534)
// Auth: admin-only — server enforces; client passes bearer token via APIClient.
//
// The `ownerPLSummary(from:to:rollup:)` method is defined in
// Networking/Endpoints/DashboardEndpoints.swift (append to existing extension).

// MARK: - Protocol

public protocol FinancialDashboardRepository: Sendable {
    /// Fetch the owner P&L summary for the given date range + rollup.
    func load(params: FinancialQueryParams) async throws -> FinancialDashboardSnapshot
}

// MARK: - Live implementation

public actor FinancialDashboardRepositoryImpl: FinancialDashboardRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load(params: FinancialQueryParams) async throws -> FinancialDashboardSnapshot {
        let wire = try await api.ownerPLSummary(
            from: params.from,
            to: params.to,
            rollup: params.rollup.rawValue
        )
        return FinancialDashboardSnapshot.from(wire: wire)
    }
}
