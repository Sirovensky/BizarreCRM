import Foundation
import Observation
import Core
import Networking

// MARK: - TenantAdminViewModel

/// Orchestrates loading of tenant info + API usage for `TenantAdminView`.
@MainActor
@Observable
public final class TenantAdminViewModel: Sendable {

    // MARK: State

    public var tenantInfo: TenantInfo?
    public var usageStats: APIUsageStats?

    public var isLoadingTenant: Bool = false
    public var isLoadingUsage: Bool = false
    public var errorMessage: String?

    public var isImpersonating: Bool = false
    public var impersonateError: String?

    // MARK: - Init

    private let api: APIClient?

    public init(api: APIClient? = nil) {
        self.api = api
    }

    // MARK: - Load

    public func load() async {
        async let tenant: Void = loadTenant()
        async let usage: Void = loadUsage()
        _ = await (tenant, usage)
    }

    private func loadTenant() async {
        guard let api else { return }
        isLoadingTenant = true
        defer { isLoadingTenant = false }
        do {
            tenantInfo = try await api.fetchTenantInfo()
        } catch let e where AppError.isCancellation(e) {
            return  // BUGHUNT-2026-05-18: nav cancel on tenant info load
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadUsage() async {
        guard let api else { return }
        isLoadingUsage = true
        defer { isLoadingUsage = false }
        do {
            usageStats = try await api.fetchAPIUsage()
        } catch {
            // Usage stats are non-critical; don't surface to user
        }
    }

    // MARK: - Sample data management

    public var isDeletingSampleData: Bool = false
    public var sampleDataError: String?
    public var sampleDataDeleted: Bool = false

    /// Removes all demo / sample data that was loaded during setup opt-in.
    /// Calls `DELETE /api/v1/onboarding/sample-data`.
    public func removeSampleData() async {
        guard let api else { return }
        isDeletingSampleData = true
        sampleDataError = nil
        defer { isDeletingSampleData = false }
        do {
            try await api.deleteOnboardingSampleData()
            sampleDataDeleted = true
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-18: bulk-delete is destructive — server
            // removes every sample row in a single tx. If the DELETE
            // committed before nav cancel, a retap on the toast would
            // re-issue the DELETE (idempotent on already-gone rows but
            // re-audits) and the user sees a confusing "failed" toast
            // for an operation that actually succeeded.
            return
        } catch {
            sampleDataError = error.localizedDescription
        }
    }

    // MARK: - Impersonation

    public func impersonate(userId: String, reason: String, managerPin: String) async -> Bool {
        guard let api else { return false }
        isImpersonating = true
        defer { isImpersonating = false }
        impersonateError = nil
        do {
            let req = ImpersonateRequest(userId: userId, reason: reason, managerPin: managerPin)
            _ = try await api.impersonateUser(req)
            return true
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: impersonateUser is a privilege-elevation
            // POST that mints a fresh impersonation token + writes an audit
            // row server-side. A `impersonateError = "cancelled"` toast
            // tempted a re-tap that — if the server had already accepted
            // the original POST — would mint a SECOND impersonation token
            // (rotating the first) and audit two start events for the same
            // operator/target. Stay silent on cancellation so the admin
            // re-confirms intent rather than reacting to a banner.
            return false
        } catch {
            impersonateError = error.localizedDescription
            return false
        }
    }
}
