import Foundation

// §1.5 Pin-from-overflow drag — NavPinCatalog
//
// Static registry of every destination that can be pinned to the primary nav.
// Duplicates the enum-case list from App/RootView.swift intentionally —
// this package must NOT import App targets (circular dependency).
//
// NEXT-STEP: In App/RootView.swift, replace hard-coded MainTab/MoreMenuView
// entries with NavPinCatalog.primaryTabs + NavPinCatalog.moreMenuItems so the
// two lists stay in sync automatically.

/// Canonical catalog of pinnable nav destinations.
///
/// Split into two groups:
/// - `primaryTabs` — the always-visible tabs / sidebar rows (MainTab cases).
/// - `moreMenuItems` — destinations currently living inside the More menu.
///
/// A `NavPinItem.id` is a stable string key — change it only in a migration.
public enum NavPinCatalog {

    // MARK: - Primary tabs (MainTab equivalents)

    /// Always-visible primary navigation destinations.
    /// These match `MainTab` in App/RootView.swift.
    public static let primaryTabs: [NavPinItem] = [
        NavPinItem(id: "tab.dashboard",  title: "Dashboard",  systemImage: "house"),
        NavPinItem(id: "tab.tickets",    title: "Tickets",    systemImage: "wrench.and.screwdriver"),
        NavPinItem(id: "tab.customers",  title: "Customers",  systemImage: "person.2"),
        NavPinItem(id: "tab.pos",        title: "POS",        systemImage: "cart"),
        NavPinItem(id: "tab.search",     title: "Search",     systemImage: "magnifyingglass"),
    ]

    // MARK: - More menu items (MoreMenuView equivalents)

    /// Overflow destinations that can be dragged into the primary nav.
    /// Grouped here to match MoreMenuView sections in App/RootView.swift.
    public static let moreMenuItems: [NavPinItem] = [
        // Operations
        NavPinItem(id: "more.inventory",    title: "Inventory",      systemImage: "shippingbox"),
        NavPinItem(id: "more.invoices",     title: "Invoices",       systemImage: "doc.text"),
        NavPinItem(id: "more.estimates",    title: "Estimates",      systemImage: "doc.badge.plus"),
        NavPinItem(id: "more.leads",        title: "Leads",          systemImage: "person.crop.circle.badge.plus"),
        NavPinItem(id: "more.appointments", title: "Appointments",   systemImage: "calendar"),
        NavPinItem(id: "more.expenses",     title: "Expenses",       systemImage: "creditcard"),
        NavPinItem(id: "more.paymentlinks", title: "Payment Links",  systemImage: "link"),
        NavPinItem(id: "more.marketing",    title: "Marketing",      systemImage: "megaphone"),
        NavPinItem(id: "more.reports",      title: "Reports",        systemImage: "chart.bar"),
        // Admin
        NavPinItem(id: "more.auditlogs",    title: "Audit Logs",     systemImage: "list.clipboard"),
        NavPinItem(id: "more.roles",        title: "Roles Matrix",   systemImage: "person.3"),
        NavPinItem(id: "more.dataimport",   title: "Data Import",    systemImage: "arrow.down.doc"),
        NavPinItem(id: "more.dataexport",   title: "Data Export",    systemImage: "arrow.up.doc"),
        NavPinItem(id: "more.priceoverride",title: "Price Overrides",systemImage: "tag"),
        NavPinItem(id: "more.devices",      title: "Device Templates",systemImage: "cpu"),
        NavPinItem(id: "more.kiosk",        title: "Kiosk Mode",     systemImage: "lock.display"),
        NavPinItem(id: "more.setup",        title: "Setup Wizard",   systemImage: "wand.and.stars"),
        // People
        NavPinItem(id: "more.employees",    title: "Employees",      systemImage: "person.badge.key"),
        NavPinItem(id: "more.sms",          title: "SMS",            systemImage: "message"),
        NavPinItem(id: "more.notifications",title: "Notifications",  systemImage: "bell"),
        NavPinItem(id: "more.calls",        title: "Calls",          systemImage: "phone"),
        NavPinItem(id: "more.voicemail",    title: "Voicemail",      systemImage: "recordingtape"),
        // Settings
        NavPinItem(id: "more.settings",     title: "Settings",       systemImage: "gearshape"),
    ]

    // MARK: - Convenience

    /// All pinnable items in a single flat array (primary first, more second).
    public static let all: [NavPinItem] = primaryTabs + moreMenuItems

    /// Look up any catalog item by stable id.
    public static func item(for id: String) -> NavPinItem? {
        all.first { $0.id == id }
    }
}
