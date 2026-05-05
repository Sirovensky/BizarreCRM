import Foundation
import Networking

// MARK: - §43.3 Price Override API Wrappers

public extension APIClient {

    /// List all overrides — optional `tenantId` or `customerId` filter.
    func listPriceOverrides(tenantId: String? = nil, customerId: String? = nil) async throws -> [PriceOverride] {
        var query: [URLQueryItem] = []
        if let t = tenantId  { query.append(URLQueryItem(name: "tenant",   value: t)) }
        if let c = customerId { query.append(URLQueryItem(name: "customer", value: c)) }
        return try await get(
            "/api/v1/repair-pricing/overrides",
            query: query.isEmpty ? nil : query,
            as: [PriceOverride].self
        )
    }

    /// Create a new price override.
    func createPriceOverride(_ body: CreatePriceOverrideRequest) async throws -> PriceOverride {
        try await post("/api/v1/repair-pricing/overrides", body: body, as: PriceOverride.self)
    }

    /// Delete a price override by id.
    func deletePriceOverride(id: String) async throws {
        try await delete("/api/v1/repair-pricing/overrides/\(id)")
    }
}
