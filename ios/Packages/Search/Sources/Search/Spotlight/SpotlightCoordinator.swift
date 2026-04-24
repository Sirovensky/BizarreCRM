import Foundation
import Observation
import Core

// MARK: - Domain notification names

public extension Notification.Name {
    /// Posted by the Tickets repository when a ticket is created/updated/deleted.
    /// `userInfo["ticket"]` may carry the updated `Ticket`.
    static let ticketChanged    = Notification.Name("bizarrecrm.ticketChanged")

    /// Posted by the Customers repository when a customer is created/updated/deleted.
    /// `userInfo["customer"]` may carry the updated `Customer`.
    static let customerChanged  = Notification.Name("bizarrecrm.customerChanged")

    /// Posted by the Inventory repository when an inventory item changes.
    /// `userInfo["inventoryItem"]` may carry the updated `InventoryItem`.
    static let inventoryChanged = Notification.Name("bizarrecrm.inventoryChanged")

    /// Posted by the Invoices repository when an invoice is created/updated/voided.
    /// `userInfo["invoiceId"]` carries the `Int64` invoice ID.
    /// `userInfo["displayId"]` carries the display order ID string (e.g. "INV-0042").
    /// `userInfo["customerName"]` carries the customer display name.
    /// `userInfo["updatedAt"]` carries the `Date` of the mutation.
    static let invoiceChanged = Notification.Name("bizarrecrm.invoiceChanged")
}

// MARK: - SpotlightCoordinator

/// Listens to domain-change notifications and drives `SpotlightIndexer`.
///
/// Debounces rapid bursts (2 s) to coalesce writes into a single batch,
/// minimising I/O pressure on the CoreSpotlight daemon.
///
/// Instantiate once at app startup (e.g. via `AppServices`) and keep alive.
/// Toggle per-domain indexing via `enabledDomains` (defaults to all on).
@MainActor
@Observable
public final class SpotlightCoordinator {

    // MARK: State (observable)

    /// Which domains are actively indexed. Mutate to enable/disable per domain.
    public var enabledDomains: Set<String> = ["tickets", "customers", "inventory"]

    // MARK: Private

    private let indexer: SpotlightIndexer
    private var pendingTickets:    [Ticket]         = []
    private var pendingCustomers:  [Customer]        = []
    private var pendingInventory:  [InventoryItem]   = []
    private var debounceTask: Task<Void, Never>?

    /// How long to wait after the last notification before flushing. 2 seconds.
    private let debounceDuration: UInt64 = 2_000_000_000

    // MARK: Init

    public init(indexer: SpotlightIndexer = SpotlightIndexer()) {
        self.indexer = indexer
        subscribeToNotifications()
    }

    // MARK: Public API

    /// Rebuild the entire Spotlight index from scratch for all enabled domains.
    ///
    /// Clears existing entries first, then hands off to the caller-provided
    /// `provider` closures to fetch fresh items per domain.
    public func rebuildAll(
        ticketProvider:    @Sendable @escaping () async -> [Ticket],
        customerProvider:  @Sendable @escaping () async -> [Customer],
        inventoryProvider: @Sendable @escaping () async -> [InventoryItem]
    ) {
        Task {
            if enabledDomains.contains("tickets") {
                let items = await ticketProvider()
                try? await indexer.batchIndex(items)
            }
            if enabledDomains.contains("customers") {
                let items = await customerProvider()
                try? await indexer.batchIndex(items)
            }
            if enabledDomains.contains("inventory") {
                let items = await inventoryProvider()
                try? await indexer.batchIndex(items)
            }
        }
    }

    // MARK: - Notification subscription

    private func subscribeToNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(
            forName: .ticketChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let ticket = notification.userInfo?["ticket"] as? Ticket
            Task { @MainActor in
                if let ticket { self.enqueueTicket(ticket) }
            }
        }

        nc.addObserver(
            forName: .customerChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let customer = notification.userInfo?["customer"] as? Customer
            Task { @MainActor in
                if let customer { self.enqueueCustomer(customer) }
            }
        }

        nc.addObserver(
            forName: .inventoryChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            let item = notification.userInfo?["inventoryItem"] as? InventoryItem
            Task { @MainActor in
                if let item { self.enqueueInventoryItem(item) }
            }
        }
    }

    // MARK: - Queue management

    private func enqueueTicket(_ ticket: Ticket) {
        guard enabledDomains.contains("tickets") else { return }
        // Deduplicate by id — keep latest
        pendingTickets.removeAll { $0.id == ticket.id }
        pendingTickets.append(ticket)
        scheduleFlush()
    }

    private func enqueueCustomer(_ customer: Customer) {
        guard enabledDomains.contains("customers") else { return }
        pendingCustomers.removeAll { $0.id == customer.id }
        pendingCustomers.append(customer)
        scheduleFlush()
    }

    private func enqueueInventoryItem(_ item: InventoryItem) {
        guard enabledDomains.contains("inventory") else { return }
        pendingInventory.removeAll { $0.id == item.id }
        pendingInventory.append(item)
        scheduleFlush()
    }

    private func scheduleFlush() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceDuration)
            if Task.isCancelled { return }
            await self.flush()
        }
    }

    @MainActor
    func flush() async {
        let tickets   = pendingTickets
        let customers = pendingCustomers
        let inventory = pendingInventory
        pendingTickets   = []
        pendingCustomers = []
        pendingInventory = []

        if !tickets.isEmpty {
            try? await indexer.batchIndex(tickets)
        }
        if !customers.isEmpty {
            try? await indexer.batchIndex(customers)
        }
        if !inventory.isEmpty {
            try? await indexer.batchIndex(inventory)
        }
    }
}
