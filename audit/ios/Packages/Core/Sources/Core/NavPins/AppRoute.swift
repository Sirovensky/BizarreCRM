import Foundation

// MARK: - §1.5 Typed route enums per tab
//
// Each feature tab declares its own route enum.  The `DeepLinkRouter` and
// `NavigationStack` path arrays use these typed values — no raw path strings
// scattered across call sites.
//
// Usage:
//   @State private var ticketsPath: [TicketsRoute] = []
//   NavigationStack(path: $ticketsPath) { ... }
//       .navigationDestination(for: TicketsRoute.self) { route in ... }

// MARK: - TicketsRoute

/// All screens reachable inside the Tickets tab.
public enum TicketsRoute: Hashable, Codable, Sendable {
    case list
    case detail(id: Int64)
    case create
    case edit(id: Int64)
    case history(id: Int64)
    case attachPhoto(ticketId: Int64)
    case addDevice(ticketId: Int64)
}

// MARK: - CustomersRoute

/// All screens reachable inside the Customers tab.
public enum CustomersRoute: Hashable, Codable, Sendable {
    case list
    case detail(id: Int64)
    case create
    case edit(id: Int64)
    case merge(keepId: Int64, mergeId: Int64)
    case loyaltyDetail(customerId: Int64)
    case newSMS(phone: String)
}

// MARK: - InventoryRoute

/// All screens reachable inside the Inventory tab.
public enum InventoryRoute: Hashable, Codable, Sendable {
    case list
    case detail(id: Int64)
    case create
    case edit(id: Int64)
    case scan
    case stocktake
    case purchaseOrders
    case purchaseOrderDetail(id: Int64)
    case receiving(poId: Int64)
}

// MARK: - InvoicesRoute

/// All screens reachable inside the Invoices tab.
public enum InvoicesRoute: Hashable, Codable, Sendable {
    case list
    case detail(id: Int64)
    case create
    case payment(invoiceId: Int64)
    case refund(invoiceId: Int64)
}

// MARK: - SMSRoute

/// All screens reachable inside the SMS / Communications tab.
public enum SMSRoute: Hashable, Codable, Sendable {
    case threadList
    case thread(phone: String)
    case compose(prefillPhone: String? = nil)
    case templates
}

// MARK: - POSRoute

/// All screens reachable inside the POS tab.
public enum POSRoute: Hashable, Codable, Sendable {
    case register
    case cart
    case cashRegister
    case giftCards
    case paymentLinks
    case returns
}

// MARK: - SettingsRoute

/// All screens reachable inside the Settings tab.
public enum SettingsRoute: Hashable, Codable, Sendable {
    case root
    case profile
    case company
    case team
    case roles
    case notifications
    case appearance
    case printers
    case hardware
    case dataImport
    case dataExport
    case auditLogs
    case dangerZone
    case diagnostics
    case help
    case about
    case featureFlags   // admin-only
    case tenantAdmin    // admin-only
}

// MARK: - DashboardRoute

/// Sub-screens reachable from the Dashboard tab.
public enum DashboardRoute: Hashable, Codable, Sendable {
    case root
    case reports(name: String)
    case notifications
}

// MARK: - AppTabRoute (top-level)

/// Top-level tab selection — wraps the per-tab route stacks.
public enum AppTabRoute: Hashable, Codable, Sendable {
    case dashboard
    case tickets
    case customers
    case inventory
    case sms
    case pos
    case settings
    case search
}
