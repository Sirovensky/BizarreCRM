import Foundation
import Networking

// MARK: - §2.1 Setup-status probe

/// Checks whether the newly-resolved server needs first-run setup or a
/// tenant selection before rendering the login form.
///
/// Called once after `LoginFlow.submitServer()` saves the base URL.
/// The probe is intentionally a lightweight value type so it can be
/// constructed inline in `LoginFlow` without DI overhead.
///
/// **UX contract** (§2.1):
/// - Response must arrive within ≤ 400 ms for a smooth transition.
///   If the request times out the caller falls through to the normal
///   login form and retries inline.
/// - `needsSetup == true`  → show `InitialSetupFlow` (§36).
/// - `isMultiTenant == true` with no saved tenant → show tenant picker.
/// - Otherwise → render the credential panel.
public struct SetupStatusProbe: Sendable {

    public enum ProbeResult: Sendable, Equatable {
        /// Server requires first-time setup wizard (§36).
        case needsSetup
        /// Server is multi-tenant and no tenant has been selected yet.
        case needsTenantPicker
        /// Proceed to credential entry.
        case proceedToLogin
        /// Probe failed — fall through to login with `error` for inline retry.
        case failed(String)

        public static func == (lhs: ProbeResult, rhs: ProbeResult) -> Bool {
            switch (lhs, rhs) {
            case (.needsSetup, .needsSetup):             return true
            case (.needsTenantPicker, .needsTenantPicker): return true
            case (.proceedToLogin, .proceedToLogin):     return true
            case (.failed(let l), .failed(let r)):       return l == r
            default: return false
            }
        }
    }

    private let api: APIClient
    /// When true the user has already selected a tenant slug; skip picker.
    private let hasSavedTenant: Bool

    public init(api: APIClient, hasSavedTenant: Bool = false) {
        self.api = api
        self.hasSavedTenant = hasSavedTenant
    }

    /// Fire the probe and translate the server response into a `ProbeResult`.
    public func run() async -> ProbeResult {
        do {
            let status = try await api.fetchAuthSetupStatus()
            if status.needsSetup {
                return .needsSetup
            }
            if status.isMultiTenant && !hasSavedTenant {
                return .needsTenantPicker
            }
            return .proceedToLogin
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
