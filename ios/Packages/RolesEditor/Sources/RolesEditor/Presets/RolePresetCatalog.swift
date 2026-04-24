import Foundation

// MARK: - RolePresetCatalog
//
// §47 Roles Capability Presets — six canonical presets for the Apply Preset
// flow.  These mirror the six roles called out in §47.2:
//   Owner / Admin / Manager / Technician / Cashier / Read-Only
//
// Capability ids are sourced from CapabilityCatalog (the single source of
// truth) — only string ids are stored here so this file stays a pure value
// with no SwiftUI or Networking dependency.

public enum RolePresetCatalog {

    // MARK: - Internal convenience sets

    private static let allCapabilityIds: Set<String> = Set(CapabilityCatalog.all.map(\.id))

    private static let coreReadIds: Set<String> = [
        "tickets.view.any",
        "customers.view",
        "inventory.view",
        "invoices.view",
        "sms.read",
        "reports.view.daily",
        "audit.view.self"
    ]

    // MARK: - Six canonical presets

    /// Owner — unrestricted access to every capability in the system.
    public static let owner = RolePresetDescriptor(
        id: "catalog.owner",
        name: "Owner",
        description: "Full access to every feature including billing, data management, and user administration.",
        capabilities: allCapabilityIds
    )

    /// Admin — same as Owner; exists as a distinct assignable role.
    public static let admin = RolePresetDescriptor(
        id: "catalog.admin",
        name: "Admin",
        description: "Full administrative access. Equivalent to Owner but useful as a delegated admin role.",
        capabilities: allCapabilityIds
    )

    /// Manager — all daily operations; cannot delete the tenant, manage billing, or wipe data.
    public static let manager = RolePresetDescriptor(
        id: "catalog.manager",
        name: "Manager",
        description: "Runs the shop day-to-day. Cannot delete the tenant account, manage billing, or wipe data.",
        capabilities: allCapabilityIds.subtracting([
            "danger.tenant.delete",
            "settings.billing",
            "danger.data.wipe",
            "data.wipe"
        ])
    )

    /// Technician — repair workflow, own tickets, parts usage, limited SMS.
    public static let technician = RolePresetDescriptor(
        id: "catalog.technician",
        name: "Technician",
        description: "Handles repair tickets, uses inventory parts, and sends SMS updates on their own tickets.",
        capabilities: [
            "tickets.view.any", "tickets.view.own",
            "tickets.create", "tickets.edit", "tickets.archive",
            "customers.view",
            "inventory.view", "inventory.adjust",
            "invoices.view",
            "sms.read", "sms.send",
            "audit.view.self"
        ]
    )

    /// Cashier — point-of-sale focused; accepts payments, creates invoices, no tech capabilities.
    public static let cashier = RolePresetDescriptor(
        id: "catalog.cashier",
        name: "Cashier",
        description: "Point-of-sale operator. Creates invoices, accepts payments, and looks up customers.",
        capabilities: [
            "tickets.view.any",
            "customers.view", "customers.create",
            "invoices.view", "invoices.create",
            "invoices.payment.accept",
            "sms.read",
            "audit.view.self"
        ]
    )

    /// Read-Only — can view all core data but cannot create, edit, or delete anything.
    public static let readOnly = RolePresetDescriptor(
        id: "catalog.read_only",
        name: "Read-Only",
        description: "View-only access across tickets, customers, inventory, and reports. Cannot change any data.",
        capabilities: coreReadIds.union([
            "reports.view.historical",
            "inventory.view",
            "audit.view.self"
        ])
    )

    // MARK: - Ordered list for UI display

    /// All six canonical presets in display order.
    public static let all: [RolePresetDescriptor] = [
        owner, admin, manager, technician, cashier, readOnly
    ]

    // MARK: - Lookup

    /// Returns the preset with the given catalog id, or `nil`.
    public static func preset(for id: String) -> RolePresetDescriptor? {
        all.first { $0.id == id }
    }
}
