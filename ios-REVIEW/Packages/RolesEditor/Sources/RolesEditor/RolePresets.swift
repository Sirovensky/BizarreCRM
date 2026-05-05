import Foundation

// MARK: - RolePreset

/// Defines a named preset role template with a hardcoded capability set.
/// §47.2 built-in presets + §47.6 detailed preset roles.
public struct RolePreset: Sendable, Hashable {
    public let id: String
    public let name: String
    public let capabilities: Set<String>

    public init(id: String, name: String, capabilities: Set<String>) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }

    /// Materialises a Role from this preset with a new UUID id.
    public func makeRole() -> Role {
        Role(id: UUID().uuidString, name: name, preset: id, capabilities: capabilities)
    }
}

// MARK: - RolePresets catalog

public enum RolePresets {

    // MARK: Convenience sets

    private static let allCapabilityIds: Set<String> = Set(CapabilityCatalog.all.map(\.id))

    private static let dailyOpsIds: Set<String> = [
        "tickets.view.any", "tickets.view.own", "tickets.create", "tickets.edit",
        "tickets.reassign", "tickets.archive",
        "customers.view", "customers.create", "customers.edit",
        "inventory.view", "inventory.adjust",
        "invoices.view", "invoices.create", "invoices.edit",
        "invoices.payment.accept",
        "sms.read", "sms.send",
        "reports.view.daily",
        "audit.view.self"
    ]

    // MARK: §47.6 Preset roles

    /// Owner — all capabilities.
    public static let owner = RolePreset(
        id: "preset.owner",
        name: "Owner",
        capabilities: allCapabilityIds
    )

    /// Manager — all except tenant.delete, billing, data.wipe.
    public static let manager = RolePreset(
        id: "preset.manager",
        name: "Manager",
        capabilities: allCapabilityIds.subtracting([
            "danger.tenant.delete",
            "settings.billing",
            "danger.data.wipe",
            "data.wipe"
        ])
    )

    /// Shift supervisor — daily ops, no settings changes.
    public static let shiftSupervisor = RolePreset(
        id: "preset.shift_supervisor",
        name: "Shift Supervisor",
        capabilities: dailyOpsIds.union([
            "tickets.price.override",
            "reports.view.historical"
        ])
    )

    /// Technician — own + assigned tickets, parts inventory, SMS for own tickets.
    public static let technician = RolePreset(
        id: "preset.technician",
        name: "Technician",
        capabilities: [
            "tickets.view.any", "tickets.view.own", "tickets.create",
            "tickets.edit", "tickets.archive",
            "customers.view",
            "inventory.view", "inventory.adjust",
            "invoices.view",
            "sms.read", "sms.send",
            "audit.view.self"
        ]
    )

    /// Cashier — POS + customers, SMS read-only, tickets view.
    public static let cashier = RolePreset(
        id: "preset.cashier",
        name: "Cashier",
        capabilities: [
            "tickets.view.any",
            "customers.view", "customers.create",
            "invoices.view", "invoices.create", "invoices.payment.accept",
            "sms.read",
            "audit.view.self"
        ]
    )

    /// Receptionist — appointments + customers + SMS + tickets create.
    public static let receptionist = RolePreset(
        id: "preset.receptionist",
        name: "Receptionist",
        capabilities: [
            "tickets.view.any", "tickets.create",
            "customers.view", "customers.create", "customers.edit",
            "sms.read", "sms.send",
            "invoices.view",
            "audit.view.self"
        ]
    )

    /// Accountant — reports + invoices + exports; no POS.
    public static let accountant = RolePreset(
        id: "preset.accountant",
        name: "Accountant",
        capabilities: [
            "invoices.view", "invoices.create", "invoices.edit",
            "invoices.void", "invoices.refund",
            "reports.view.daily", "reports.view.historical", "reports.export",
            "customers.view", "customers.export",
            "data.export",
            "audit.view.self"
        ]
    )

    // MARK: §47.2 built-in system presets

    /// Admin — same as owner for the built-in list.
    public static let admin = RolePreset(
        id: "preset.admin",
        name: "Admin",
        capabilities: allCapabilityIds
    )

    /// Viewer — read-only across main domains.
    public static let viewer = RolePreset(
        id: "preset.viewer",
        name: "Viewer",
        capabilities: [
            "tickets.view.any",
            "customers.view",
            "inventory.view",
            "invoices.view",
            "sms.read",
            "reports.view.daily", "reports.view.historical",
            "audit.view.self"
        ]
    )

    /// Training — minimal read-only for new staff onboarding.
    public static let training = RolePreset(
        id: "preset.training",
        name: "Training",
        capabilities: [
            "tickets.view.own",
            "customers.view",
            "inventory.view",
            "audit.view.self"
        ]
    )

    // MARK: All presets ordered for UI display

    public static let all: [RolePreset] = [
        owner, admin, manager, shiftSupervisor,
        technician, cashier, receptionist, accountant,
        viewer, training
    ]

    /// Returns the preset matching the given id.
    public static func preset(for id: String) -> RolePreset? {
        all.first { $0.id == id }
    }

    /// Clones a role into a new custom role with a new id and name.
    public static func cloneRole(_ role: Role, newName: String) -> Role {
        Role(id: UUID().uuidString, name: newName, preset: nil, capabilities: role.capabilities)
    }
}
