import Foundation
import Persistence
import Networking
import Core

// MARK: - TenantStore

/// Actor that owns the multi-tenant session state.
///
/// **Host wiring (AppServices.swift):**
/// After `switchTo` completes the host *must* flush per-tenant repositories and
/// navigate to the dashboard. Wire the `onTenantSwitch` closure at startup:
///
/// ```swift
/// TenantStore.shared = TenantStore(
///     repository: LiveTenantRepository(api: api),
///     api: api,
///     onTenantSwitch: { tenant in
///         await appServices.reconfigureForTenant(tenant)
///     }
/// )
/// ```
///
/// The notification `.tenantDidSwitch` is also posted so any other observer
/// (widgets, deep-link router) can react without holding a reference to AppServices.
public actor TenantStore {
    // MARK: Public state

    /// The currently-active tenant. `nil` until first `load()` or `switchTo` call.
    public private(set) var active: Tenant?

    /// Full list of tenants the user belongs to, in most-recently-accessed order.
    public private(set) var known: [Tenant] = []

    // MARK: Dependencies

    private let repository: any TenantRepository
    private let api: any APIClient
    /// Host closure called after a successful tenant switch so AppServices can
    /// reconfigure repositories, flush caches, and redirect navigation.
    private let onTenantSwitch: @Sendable (Tenant) async -> Void

    // MARK: Init

    public init(
        repository: any TenantRepository,
        api: any APIClient,
        onTenantSwitch: @Sendable @escaping (Tenant) async -> Void = { _ in }
    ) {
        self.repository = repository
        self.api = api
        self.onTenantSwitch = onTenantSwitch
    }

    // MARK: - Public API

    /// Fetches the user's tenant list from the server, updates `known`, and
    /// reconciles `active` against the persisted `activeTenantId`.
    @discardableResult
    public func load() async throws -> [Tenant] {
        let tenants = try await repository.loadTenants()
        // Most-recently-accessed first.
        let sorted = tenants.sorted {
            ($0.lastAccessedAt ?? .distantPast) > ($1.lastAccessedAt ?? .distantPast)
        }
        known = sorted

        // Restore active from Keychain if the tenant is still in the list.
        let savedId = KeychainStore.shared.get(.activeTenantId)
        if let id = savedId, let match = sorted.first(where: { $0.id == id }) {
            active = match
        } else if active == nil {
            active = sorted.first
        }

        return sorted
    }

    /// Switches to the specified tenant:
    /// 1. POSTs to `/auth/tenant/switch` to get a new scoped token.
    /// 2. Updates `APIClient` auth token and base URL.
    /// 3. Persists `activeTenantId` in Keychain.
    /// 4. Calls the host `onTenantSwitch` closure.
    /// 5. Posts `.tenantDidSwitch` notification.
    public func switchTo(tenantId: String) async throws {
        guard let tenant = known.first(where: { $0.id == tenantId }) else {
            throw AppError.notFound(entity: "Tenant \(tenantId)")
        }

        // BUGHUNT-2026-05-17: was `let (accessToken, _) = …` — the new
        // refresh token from the server was being discarded. Pair that with
        // the direct `KeychainStore.shared.set(accessToken, for: .accessToken)`
        // below and TokenStore's in-memory cache stayed stale (load() only
        // hits Keychain once per process), so any subsequent AuthRefresher
        // run would post the OLD tenant's refresh token to /auth/refresh and
        // be force-signed-out. Capture both tokens and route through
        // TokenStore.save so the cache + Keychain stay in lock-step.
        let (accessToken, refreshToken) = try await repository.switchTenant(tenantId: tenantId)

        // Update APIClient — token first, then base URL if tenant has its own.
        await api.setAuthToken(accessToken)
        if let url = tenant.baseURL {
            await api.setBaseURL(url)
        }

        // Persist new active tenant ID.
        do {
            try KeychainStore.shared.set(tenantId, for: .activeTenantId)
        } catch {
            AppLog.auth.error("TenantStore: failed to persist activeTenantId: \(error.localizedDescription)")
        }

        // Persist new token pair atomically through TokenStore so the in-
        // memory cache + Keychain stay consistent. Writing Keychain directly
        // here would leave TokenStore's `_access` / `_refresh` pointing at
        // the previous tenant's pair until the next process restart.
        await MainActor.run {
            TokenStore.shared.save(access: accessToken, refresh: refreshToken)
        }

        active = tenant

        // Notify host.
        await onTenantSwitch(tenant)

        // Broadcast for other observers.
        let captured = tenant
        await MainActor.run {
            NotificationCenter.default.post(
                name: .tenantDidSwitch,
                object: nil,
                userInfo: ["tenant": captured]
            )
        }
    }

    /// Convenience: switch using a full `Tenant` value.
    public func switchTo(tenant: Tenant) async throws {
        try await switchTo(tenantId: tenant.id)
    }

    /// Clears the active-tenant record from Keychain (call during sign-out).
    public func clearActiveSession() {
        try? KeychainStore.shared.remove(.activeTenantId)
        active = nil
        known = []
    }
}
