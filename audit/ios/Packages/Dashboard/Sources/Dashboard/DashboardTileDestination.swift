import Foundation

// MARK: - DashboardTileDestination
//
// §3.1 — Navigation destinations for KPI tile taps.
//
// Each case describes WHERE the user should be taken when they tap a tile.
// The App layer maps these cases to `NavigationPath` pushes or
// `DeepLinkRouter.shared.handle(_:)` calls.
//
// **Wiring (Discovered §3.1):**
// `DeepLinkRoute` in `Core/DeepLinkParser.swift` does not yet have filtered-list
// cases (`.ticketList`, `.inventoryList`, `.appointmentList`).
// Agent 10 must add those cases and update `DeepLinkParser.route(...)` before
// App-layer deep-link routing can fully resolve these destinations.
// The `DashboardTileDestination` API here is stable and ready for wiring.

public enum DashboardTileDestination: Sendable, Hashable {

    // MARK: Ticket list variants

    /// Ticket list pre-filtered by a server-side query string fragment.
    /// e.g. `filter = "status_group=open"` or `"status_group=closed&closed_today=true"`.
    case ticketList(filter: String)

    // MARK: Inventory

    /// Inventory list pre-filtered by a query string fragment.
    /// e.g. `filter = "low_stock=true"` or `""` for all inventory.
    case inventoryList(filter: String)

    // MARK: Appointments

    /// Appointment list pre-filtered by a query string fragment.
    /// e.g. `filter = "date=today"`.
    case appointmentList(filter: String)

    // MARK: Reports / KPI detail

    /// Named report page (maps to `reports/<name>`).
    /// e.g. `name = "net-profit"`, `"refunds"`, `"expenses"`.
    case reports(name: String)

    // MARK: Financial summary

    /// Revenue-today financial summary / sales report.
    case revenueToday
}

public extension DashboardTileDestination {

    /// Human-readable description for accessibility hints and logging.
    var accessibilityDescription: String {
        switch self {
        case .ticketList(let filter):
            return filter.contains("open") ? "open tickets" : "closed tickets"
        case .inventoryList(let filter):
            return filter.contains("low_stock") ? "low stock inventory" : "inventory"
        case .appointmentList:
            return "today's appointments"
        case .reports(let name):
            return "\(name) report"
        case .revenueToday:
            return "revenue today report"
        }
    }
}
