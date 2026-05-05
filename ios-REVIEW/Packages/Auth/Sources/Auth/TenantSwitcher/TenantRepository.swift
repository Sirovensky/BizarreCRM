import Foundation
import Networking
import Core

// MARK: - Protocol

/// Abstracts tenant data fetching so `TenantStore` and tests can use stubs.
public protocol TenantRepository: Sendable {
    /// Fetch the authenticated user's full tenant list from the server.
    func loadTenants() async throws -> [Tenant]
    /// Exchange tokens scoped to `tenantId`.
    func switchTenant(tenantId: String) async throws -> (accessToken: String, refreshToken: String)
    /// Revoke the current tenant session server-side (non-fatal).
    func revokeTenantSession() async throws
}

// MARK: - Live implementation

/// Concrete implementation backed by `APIClient`.
public struct LiveTenantRepository: TenantRepository {
    private let api: any APIClient

    public init(api: any APIClient) {
        self.api = api
    }

    public func loadTenants() async throws -> [Tenant] {
        do {
            return try await api.fetchTenants()
        } catch {
            throw AppError.from(error)
        }
    }

    public func switchTenant(tenantId: String) async throws -> (accessToken: String, refreshToken: String) {
        do {
            let resp = try await api.switchTenant(tenantId: tenantId)
            return (resp.accessToken, resp.refreshToken)
        } catch {
            throw AppError.from(error)
        }
    }

    public func revokeTenantSession() async throws {
        // Non-fatal: swallow errors so sign-out always completes locally.
        try? await api.revokeTenantSession()
    }
}
