import Foundation
import Networking

// MARK: - Request / Response DTOs (module-internal)

/// Request body for POST /api/v1/auth/tenant/switch
struct TenantSwitchRequest: Encodable, Sendable {
    let tenantId: String
}

/// Token response returned by the switch endpoint.
struct TenantSwitchResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
}

/// Response from GET /api/v1/auth/tenants
struct TenantsListResponse: Decodable, Sendable {
    let tenants: [Tenant]
}

/// Empty body for POST /api/v1/auth/tenant/revoke-session
private struct EmptyBody: Encodable, Sendable { init() {} }

// MARK: - APIClient extension (internal — called only from LiveTenantRepository)

extension APIClient {
    /// GET /api/v1/auth/tenants — returns all tenants the user belongs to.
    func fetchTenants() async throws -> [Tenant] {
        let resp = try await get("/api/v1/auth/tenants", as: TenantsListResponse.self)
        return resp.tenants
    }

    /// POST /api/v1/auth/tenant/switch — exchange a new token scoped to the target tenant.
    func switchTenant(tenantId: String) async throws -> TenantSwitchResponse {
        try await post(
            "/api/v1/auth/tenant/switch",
            body: TenantSwitchRequest(tenantId: tenantId),
            as: TenantSwitchResponse.self
        )
    }

    /// POST /api/v1/auth/tenant/revoke-session — revoke server-side session for current tenant.
    /// Non-fatal — caller should always clear local state regardless of result.
    func revokeTenantSession() async throws {
        _ = try await post(
            "/api/v1/auth/tenant/revoke-session",
            body: EmptyBody(),
            as: LogoutResponse.self
        )
    }
}
