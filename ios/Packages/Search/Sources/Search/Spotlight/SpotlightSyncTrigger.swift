import Foundation
import Core

// MARK: - §25.1 Spotlight refresh triggered by sync-complete
//
// Subscribes to `Notification.Name.syncComplete` (posted by `SyncOrchestrator`
// after a successful delta sync). On receipt it calls `SpotlightCoordinator.flush()`
// to drain any pending items accumulated during the sync window, and calls
// `rebuildAll` with providers when a full rebuild is needed (schema migration or
// first launch after install).
//
// Index window per §25.1 spec:
//   - Tickets:      last 60 days  (created_at or updated_at within window)
//   - Customers:    top 500       (most recent 500 by updated_at)
//   - Invoices:     top 200
//   - Appointments: top 100
//   - Inventory:    all active SKUs (no window — catalog changes infrequently)

// MARK: - Notification name (posted by SyncOrchestrator after sync)

public extension Notification.Name {
    /// Posted by `SyncOrchestrator` after a successful delta sync round.
    /// `userInfo["isFullRebuild"]` is `true` when the sync was a full reset.
    static let syncComplete = Notification.Name("bizarrecrm.syncComplete")
}

// MARK: - Index window constants (§25.1)

public enum SpotlightIndexWindow {
    /// Tickets: last N days
    public static let ticketDays: Int = 60
    /// Customers: top N by recency
    public static let customerLimit: Int = 500
    /// Invoices: top N by recency
    public static let invoiceLimit: Int = 200
    /// Appointments: top N by recency
    public static let appointmentLimit: Int = 100
    /// Inventory: all active SKUs (nil = no limit)
    public static let inventoryLimit: Int? = nil
}

// MARK: - Trigger

/// Connects `SyncOrchestrator` events to `SpotlightCoordinator`.
///
/// Instantiate once at app startup (e.g. in `AppServices`) and keep alive.
/// The object registers for `syncComplete` notifications and drives re-indexing.
///
/// **Usage:**
/// ```swift
/// let trigger = SpotlightSyncTrigger(coordinator: spotlightCoordinator)
/// trigger.start(
///     ticketProvider: { await ticketRepo.recentTickets(days: SpotlightIndexWindow.ticketDays) },
///     customerProvider: { await customerRepo.topCustomers(limit: SpotlightIndexWindow.customerLimit) },
///     inventoryProvider: { await inventoryRepo.allActive() }
/// )
/// ```
@MainActor
public final class SpotlightSyncTrigger {
    private let coordinator: SpotlightCoordinator
    private var observer: NSObjectProtocol?

    private var ticketProvider: (@Sendable () async -> [Ticket])?
    private var customerProvider: (@Sendable () async -> [Customer])?
    private var inventoryProvider: (@Sendable () async -> [InventoryItem])?

    public init(coordinator: SpotlightCoordinator) {
        self.coordinator = coordinator
    }

    deinit {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// Start observing sync-complete events. Call once at app startup.
    public func start(
        ticketProvider: @Sendable @escaping () async -> [Ticket],
        customerProvider: @Sendable @escaping () async -> [Customer],
        inventoryProvider: @Sendable @escaping () async -> [InventoryItem]
    ) {
        self.ticketProvider = ticketProvider
        self.customerProvider = customerProvider
        self.inventoryProvider = inventoryProvider

        observer = NotificationCenter.default.addObserver(
            forName: .syncComplete,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let isFullRebuild = notification.userInfo?["isFullRebuild"] as? Bool ?? false
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.handleSyncComplete(isFullRebuild: isFullRebuild)
            }
        }
        AppLog.ui.info("SpotlightSyncTrigger: started — watching syncComplete notifications")
    }

    /// Stop observing. Safe to call multiple times.
    public func stop() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    // MARK: - Private

    private func handleSyncComplete(isFullRebuild: Bool) async {
        if isFullRebuild {
            AppLog.ui.info("SpotlightSyncTrigger: full rebuild triggered")
            await fullRebuild()
        } else {
            // Incremental: flush pending changes accumulated since last sync
            AppLog.ui.debug("SpotlightSyncTrigger: incremental flush triggered")
            await coordinator.flush()
        }
    }

    private func fullRebuild() async {
        guard
            let ticketProvider,
            let customerProvider,
            let inventoryProvider
        else {
            AppLog.ui.warning("SpotlightSyncTrigger: fullRebuild called but providers not set — skip")
            return
        }
        coordinator.rebuildAll(
            ticketProvider: ticketProvider,
            customerProvider: customerProvider,
            inventoryProvider: inventoryProvider
        )
    }
}
