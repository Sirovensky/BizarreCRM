import Foundation
import Networking

// MARK: - DashboardBIEndpoints
//
// APIClient extensions for BI widget data.
// Satisfies §20 containment: BI ViewModels call these, not api.get() directly.

public extension APIClient {

    /// `GET /api/v1/reports/dashboard` — full dashboard payload.
    /// Decoded by the caller into a domain-specific partial decode.
    func fetchDashboardTopServices() async throws -> DashboardTopServicesResult {
        try await get("/api/v1/reports/dashboard", as: DashboardTopServicesResult.self)
    }
}

// MARK: - DTO

public struct DashboardTopServicesResult: Decodable, Sendable {
    public let topServices: [TopServiceEntry]

    public init(topServices: [TopServiceEntry] = []) {
        self.topServices = topServices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.topServices = (try? c.decode([TopServiceEntry].self, forKey: .topServices)) ?? []
    }

    enum CodingKeys: String, CodingKey { case topServices = "top_services" }
}
