import Foundation
import Networking

/// §18 — Per-entity hit counts shown as badges on scope filter chips.
///
/// Counts are derived from the union of local FTS hits + remote server results
/// so the badge is immediately available from the local index even offline.
public struct ScopeCounts: Sendable, Equatable {
    public var all: Int
    public var customers: Int
    public var tickets: Int
    public var inventory: Int
    public var invoices: Int
    public var estimates: Int
    public var appointments: Int

    public static let zero = ScopeCounts(
        all: 0, customers: 0, tickets: 0,
        inventory: 0, invoices: 0, estimates: 0, appointments: 0
    )

    public init(
        all: Int = 0,
        customers: Int = 0,
        tickets: Int = 0,
        inventory: Int = 0,
        invoices: Int = 0,
        estimates: Int = 0,
        appointments: Int = 0
    ) {
        self.all = all
        self.customers = customers
        self.tickets = tickets
        self.inventory = inventory
        self.invoices = invoices
        self.estimates = estimates
        self.appointments = appointments
    }

    /// Count for a specific `EntityFilter`. Returns `all` for `.all`.
    public func count(for filter: EntityFilter) -> Int {
        switch filter {
        case .all:          return all
        case .customers:    return customers
        case .tickets:      return tickets
        case .inventory:    return inventory
        case .invoices:     return invoices
        case .estimates:    return estimates
        case .appointments: return appointments
        }
    }

    // MARK: - Builders

    /// Build counts from a flat array of `SearchHit` (local FTS results).
    public static func from(localHits: [SearchHit]) -> ScopeCounts {
        var c = ScopeCounts()
        for hit in localHits {
            switch hit.entity {
            case "customers":    c.customers += 1
            case "tickets":      c.tickets += 1
            case "inventory":    c.inventory += 1
            case "invoices":     c.invoices += 1
            case "estimates":    c.estimates += 1
            case "appointments": c.appointments += 1
            default: break
            }
        }
        c.all = c.customers + c.tickets + c.inventory + c.invoices + c.estimates + c.appointments
        return c
    }

    /// Merge local counts with remote `GlobalSearchResults` counts, taking the
    /// max per entity so the badge never decreases when the server responds.
    public func merged(with remote: GlobalSearchResults) -> ScopeCounts {
        let mergedCustomers    = max(customers, remote.customers.count)
        let mergedTickets      = max(tickets, remote.tickets.count)
        let mergedInventory    = max(inventory, remote.inventory.count)
        let mergedInvoices     = max(invoices, remote.invoices.count)
        let mergedAll = mergedCustomers + mergedTickets + mergedInventory + mergedInvoices + estimates + appointments
        return ScopeCounts(
            all: mergedAll,
            customers: mergedCustomers,
            tickets: mergedTickets,
            inventory: mergedInventory,
            invoices: mergedInvoices,
            estimates: estimates,
            appointments: appointments
        )
    }
}
