import Foundation
import Networking
import Persistence
import Auth
import Settings
import Customers
import Tickets
import Inventory
import Pos
import Sync
import Hardware

/// Shared services that must share state across the whole app. Most
/// importantly the APIClient: LoginFlow writes the bearer token and base URL
/// to this instance, Dashboard and every other feature reads from the same
/// instance so the session carries. Replace with a full Factory container
/// once more features come online.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let apiClient: APIClient

    /// §17.4 — Cash drawer. Defaults to `NullCashDrawer` (throws
    /// `CashDrawerError.notConnected`) until a paired printer is configured.
    /// When `EscPosNetworkEngine` gains `EscPosSender` conformance, replace
    /// with `EscPosDrawerKick(sender: EscPosNetworkEngine(config: printerConfig))`.
    let cashDrawer: any CashDrawer = NullCashDrawer()

    private init() {
        self.apiClient = APIClientImpl(initialBaseURL: ServerURLStore.load())
        // Expose to packages that can't import Auth/App (Settings, etc.).
        APIClientHolder.current = self.apiClient
    }

    /// Push any persisted credentials into the APIClient. Call once at launch
    /// so a cold-started user with a valid session doesn't need to re-auth.
    /// Also wires the §2.11 token refresher so the client can auto-recover
    /// from expired access tokens without bouncing the user to Login.
    func restoreSession() async {
        if let token = TokenStore.shared.accessToken {
            await apiClient.setAuthToken(token)
        }
        if let url = ServerURLStore.load() {
            await apiClient.setBaseURL(url)
        }
        // Wire the refresher. Doing it here (vs LoginFlow) means even a
        // cold launch with an expired access token can refresh silently
        // before the first API call.
        let refresher = AuthRefresher(apiClient: apiClient)
        await apiClient.setRefresher(refresher)

        // §20.3 — register the per-domain replay handlers so the
        // SyncOrchestrator's first flush has somewhere to route the work.
        // Adding a new domain? Add its `register(api:)` call here.
        await CustomerSyncHandlers.register(api: apiClient)
        await TicketSyncHandlers.register(api: apiClient)
        await InventorySyncHandlers.register(api: apiClient)

        // §16 / SEC-2 — POS offline sync executor. Handles pos.sale.finalize,
        // pos.return.create, and pos.cash.opening ops that were enqueued while
        // offline. Without this the drain loop has no executor and POS ops are
        // permanently stranded.
        // TODO: When Invoices/Appointments/Expenses/SMS/Employees also gain
        // offline-write executors, replace with a CompositeSyncOpExecutor
        // that dispatches by op.entity prefix to the right domain executor.
        let posExecutor = PosSyncOpExecutor(api: apiClient)
        SyncManager.shared.executor = posExecutor
        SyncManager.shared.autoStart()
    }
}
