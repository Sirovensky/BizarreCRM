import Foundation
import Observation
import Core

/// §18.3 — Listens to domain-change notifications and drives `FTSIndexStore`.
///
/// Mirrors the `SpotlightCoordinator` pattern: debounces rapid bursts (1 s)
/// to coalesce writes. Instantiate once at app launch via `AppServices`.
@MainActor
@Observable
public final class FTSReindexCoordinator {

    // MARK: - State

    public private(set) var lastIndexedAt: Date?
    public private(set) var isIndexing: Bool = false

    // MARK: - Private

    private let ftsStore: FTSIndexStore
    private var pendingTickets: [Ticket] = []
    private var pendingCustomers: [Customer] = []
    private var pendingInventory: [InventoryItem] = []

    /// Invoice changes carry plain fields — no Invoice domain model in Core yet.
    private struct PendingInvoice: Sendable {
        let id: Int64
        let displayId: String
        let customerName: String
        let updatedAt: Date
    }

    private var pendingInvoices: [PendingInvoice] = []
    private var debounceTask: Task<Void, Never>?
    private let debounceDuration: UInt64 = 1_000_000_000  // 1 s

    // MARK: - Init

    public init(ftsStore: FTSIndexStore) {
        self.ftsStore = ftsStore
        subscribeToNotifications()
    }

    // MARK: - Bulk rebuild

    /// One invoice row for bulk rebuild — mirrors the invoice fields indexed in the FTS store.
    public struct InvoiceIndexEntry: Sendable {
        public let id: Int64
        public let displayId: String
        public let customerName: String
        public let updatedAt: Date

        public init(id: Int64, displayId: String, customerName: String, updatedAt: Date) {
            self.id = id
            self.displayId = displayId
            self.customerName = customerName
            self.updatedAt = updatedAt
        }
    }

    /// Call on app launch after initial GRDB sync. Provider closures fetch
    /// from the local database — no network calls here.
    public func rebuildAll(
        ticketProvider: @Sendable @escaping () async -> [Ticket],
        customerProvider: @Sendable @escaping () async -> [Customer],
        inventoryProvider: @Sendable @escaping () async -> [InventoryItem],
        invoiceProvider: (@Sendable () async -> [InvoiceIndexEntry])? = nil
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isIndexing = true
            defer { self.isIndexing = false }

            let tickets = await ticketProvider()
            for ticket in tickets {
                try? await self.ftsStore.indexTicket(ticket)
            }

            let customers = await customerProvider()
            for customer in customers {
                try? await self.ftsStore.indexCustomer(customer)
            }

            let items = await inventoryProvider()
            for item in items {
                try? await self.ftsStore.indexInventory(item)
            }

            if let invoiceProvider {
                let invoices = await invoiceProvider()
                for invoice in invoices {
                    try? await self.ftsStore.indexInvoice(
                        id: invoice.id,
                        displayId: invoice.displayId,
                        customerName: invoice.customerName,
                        updatedAt: invoice.updatedAt
                    )
                }
            }

            self.lastIndexedAt = Date()
        }
    }

    // MARK: - Notification subscriptions

    private func subscribeToNotifications() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: .ticketChanged, object: nil, queue: nil) { [weak self] note in
            guard let self, let ticket = note.userInfo?["ticket"] as? Ticket else { return }
            Task { @MainActor in self.enqueueTicket(ticket) }
        }

        nc.addObserver(forName: .customerChanged, object: nil, queue: nil) { [weak self] note in
            guard let self, let customer = note.userInfo?["customer"] as? Customer else { return }
            Task { @MainActor in self.enqueueCustomer(customer) }
        }

        nc.addObserver(forName: .inventoryChanged, object: nil, queue: nil) { [weak self] note in
            guard let self, let item = note.userInfo?["inventoryItem"] as? InventoryItem else { return }
            Task { @MainActor in self.enqueueInventoryItem(item) }
        }

        nc.addObserver(forName: .invoiceChanged, object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let id = info["invoiceId"] as? Int64,
                  let displayId = info["displayId"] as? String,
                  let customerName = info["customerName"] as? String,
                  let updatedAt = info["updatedAt"] as? Date
            else { return }
            let pending = PendingInvoice(
                id: id, displayId: displayId,
                customerName: customerName, updatedAt: updatedAt
            )
            Task { @MainActor in self.enqueueInvoice(pending) }
        }
    }

    // MARK: - Queue management

    private func enqueueTicket(_ ticket: Ticket) {
        pendingTickets.removeAll { $0.id == ticket.id }
        pendingTickets.append(ticket)
        scheduleFlush()
    }

    private func enqueueCustomer(_ customer: Customer) {
        pendingCustomers.removeAll { $0.id == customer.id }
        pendingCustomers.append(customer)
        scheduleFlush()
    }

    private func enqueueInventoryItem(_ item: InventoryItem) {
        pendingInventory.removeAll { $0.id == item.id }
        pendingInventory.append(item)
        scheduleFlush()
    }

    private func enqueueInvoice(_ invoice: PendingInvoice) {
        pendingInvoices.removeAll { $0.id == invoice.id }
        pendingInvoices.append(invoice)
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
        let tickets = pendingTickets
        let customers = pendingCustomers
        let inventory = pendingInventory
        let invoices = pendingInvoices
        pendingTickets = []
        pendingCustomers = []
        pendingInventory = []
        pendingInvoices = []

        isIndexing = !tickets.isEmpty || !customers.isEmpty || !inventory.isEmpty || !invoices.isEmpty
        defer { isIndexing = false }

        for ticket in tickets { try? await ftsStore.indexTicket(ticket) }
        for customer in customers { try? await ftsStore.indexCustomer(customer) }
        for item in inventory { try? await ftsStore.indexInventory(item) }
        for invoice in invoices {
            try? await ftsStore.indexInvoice(
                id: invoice.id,
                displayId: invoice.displayId,
                customerName: invoice.customerName,
                updatedAt: invoice.updatedAt
            )
        }

        if !tickets.isEmpty || !customers.isEmpty || !inventory.isEmpty || !invoices.isEmpty {
            lastIndexedAt = Date()
        }
    }
}
