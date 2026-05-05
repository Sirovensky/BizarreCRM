import Foundation

// MARK: - CapabilityCatalog

/// Hardcoded catalog of all ~80 fine-grained capabilities across all domains.
/// This mirrors the ActionPlan §47.5 specification exactly.
public enum CapabilityCatalog {

    // MARK: All capabilities

    public static let all: [Capability] = tickets + customers + inventory +
        invoices + sms + reports + settings + hardware + audit + data + team +
        marketing + danger

    // MARK: - Tickets (8)

    public static let tickets: [Capability] = [
        Capability(id: "tickets.view.any",       domain: "Tickets", label: "View any ticket",          description: "See all tickets regardless of assignment"),
        Capability(id: "tickets.view.own",        domain: "Tickets", label: "View own tickets",         description: "See only tickets assigned to self"),
        Capability(id: "tickets.create",          domain: "Tickets", label: "Create ticket",            description: "Open new repair / service tickets"),
        Capability(id: "tickets.edit",            domain: "Tickets", label: "Edit ticket",              description: "Modify ticket details, notes, and status"),
        Capability(id: "tickets.delete",          domain: "Tickets", label: "Delete ticket",            description: "Permanently remove tickets"),
        Capability(id: "tickets.reassign",        domain: "Tickets", label: "Reassign ticket",          description: "Change the technician assigned to a ticket"),
        Capability(id: "tickets.archive",         domain: "Tickets", label: "Archive ticket",           description: "Move closed tickets to archive"),
        Capability(id: "tickets.price.override",  domain: "Tickets", label: "Override price",           description: "Change the quoted or final price on a ticket")
    ]

    // MARK: - Customers (5)

    public static let customers: [Capability] = [
        Capability(id: "customers.view",    domain: "Customers", label: "View customers",   description: "Browse and search the customer list"),
        Capability(id: "customers.create",  domain: "Customers", label: "Create customer",  description: "Add new customer records"),
        Capability(id: "customers.edit",    domain: "Customers", label: "Edit customer",    description: "Update customer contact and profile info"),
        Capability(id: "customers.delete",  domain: "Customers", label: "Delete customer",  description: "Remove customer records permanently"),
        Capability(id: "customers.export",  domain: "Customers", label: "Export customers", description: "Download customer data as CSV")
    ]

    // MARK: - Inventory (8)

    public static let inventory: [Capability] = [
        Capability(id: "inventory.view",    domain: "Inventory", label: "View inventory",    description: "Browse parts and products"),
        Capability(id: "inventory.create",  domain: "Inventory", label: "Add item",          description: "Create new inventory items"),
        Capability(id: "inventory.edit",    domain: "Inventory", label: "Edit item",         description: "Update inventory item details and pricing"),
        Capability(id: "inventory.adjust",  domain: "Inventory", label: "Adjust stock",      description: "Record stock adjustments and discrepancies"),
        Capability(id: "inventory.delete",  domain: "Inventory", label: "Delete item",       description: "Remove inventory items permanently"),
        Capability(id: "inventory.import",  domain: "Inventory", label: "Import inventory",  description: "Bulk-import items from CSV or supplier feed"),
        Capability(id: "inventory.export",  domain: "Inventory", label: "Export inventory",  description: "Download inventory as CSV"),
        Capability(id: "inventory.reorder", domain: "Inventory", label: "Manage reorders",   description: "Set reorder points and trigger purchase orders")
    ]

    // MARK: - Invoices (7)

    public static let invoices: [Capability] = [
        Capability(id: "invoices.view",            domain: "Invoices", label: "View invoices",       description: "Browse and search invoices"),
        Capability(id: "invoices.create",          domain: "Invoices", label: "Create invoice",      description: "Generate new invoices"),
        Capability(id: "invoices.edit",            domain: "Invoices", label: "Edit invoice",        description: "Modify draft invoices"),
        Capability(id: "invoices.void",            domain: "Invoices", label: "Void invoice",        description: "Cancel an issued invoice"),
        Capability(id: "invoices.refund",          domain: "Invoices", label: "Issue refund",        description: "Refund a paid invoice"),
        Capability(id: "invoices.payment.accept",  domain: "Invoices", label: "Accept payment",      description: "Record cash, card, or external payments"),
        Capability(id: "invoices.payment.refund",  domain: "Invoices", label: "Refund payment",      description: "Reverse a recorded payment")
    ]

    // MARK: - SMS (4)

    public static let sms: [Capability] = [
        Capability(id: "sms.read",       domain: "SMS", label: "Read messages",      description: "View SMS conversations"),
        Capability(id: "sms.send",       domain: "SMS", label: "Send message",       description: "Send individual SMS to customers"),
        Capability(id: "sms.delete",     domain: "SMS", label: "Delete message",     description: "Remove SMS messages from conversations"),
        Capability(id: "sms.broadcast",  domain: "SMS", label: "Send broadcast",     description: "Send mass SMS to customer segments")
    ]

    // MARK: - Reports (3)

    public static let reports: [Capability] = [
        Capability(id: "reports.view.daily",      domain: "Reports", label: "View daily reports",      description: "Access today's sales and activity summaries"),
        Capability(id: "reports.view.historical", domain: "Reports", label: "View historical reports",  description: "Access reports across any date range"),
        Capability(id: "reports.export",          domain: "Reports", label: "Export reports",           description: "Download report data as CSV or PDF")
    ]

    // MARK: - Settings (8)

    public static let settings: [Capability] = [
        Capability(id: "settings.view",           domain: "Settings", label: "View settings",          description: "Access the settings panel"),
        Capability(id: "settings.edit.org",       domain: "Settings", label: "Edit org info",          description: "Update business name, address, logo"),
        Capability(id: "settings.edit.payment",   domain: "Settings", label: "Edit payment config",    description: "Configure payment processors and terminals"),
        Capability(id: "settings.edit.tax",       domain: "Settings", label: "Edit tax rates",         description: "Set regional tax rates and rules"),
        Capability(id: "settings.edit.sms",       domain: "Settings", label: "Edit SMS settings",      description: "Configure Twilio and messaging templates"),
        Capability(id: "settings.edit.roles",     domain: "Settings", label: "Manage roles",           description: "Create, edit, and delete user roles"),
        Capability(id: "settings.edit.templates", domain: "Settings", label: "Edit templates",         description: "Manage invoice, email, and SMS templates"),
        Capability(id: "settings.billing",        domain: "Settings", label: "Manage billing",         description: "View subscription, usage, and invoices")
    ]

    // MARK: - Hardware (3)

    public static let hardware: [Capability] = [
        Capability(id: "hardware.printer.config",  domain: "Hardware", label: "Configure printers",   description: "Set up and manage receipt printers"),
        Capability(id: "hardware.terminal.config", domain: "Hardware", label: "Configure terminals",  description: "Pair and manage card payment terminals"),
        Capability(id: "hardware.scanner.config",  domain: "Hardware", label: "Configure scanners",   description: "Set up barcode and QR scanners")
    ]

    // MARK: - Audit (2)

    public static let audit: [Capability] = [
        Capability(id: "audit.view.self", domain: "Audit", label: "View own audit trail",  description: "See your own action history"),
        Capability(id: "audit.view.all",  domain: "Audit", label: "View all audit logs",   description: "See all users' action history")
    ]

    // MARK: - Data (5)

    public static let data: [Capability] = [
        Capability(id: "data.import",  domain: "Data", label: "Import data",  description: "Import external data files"),
        Capability(id: "data.export",  domain: "Data", label: "Export data",  description: "Export tenant data"),
        Capability(id: "data.backup",  domain: "Data", label: "Backup data",  description: "Create encrypted data backups"),
        Capability(id: "data.restore", domain: "Data", label: "Restore data", description: "Restore from a backup"),
        Capability(id: "data.wipe",    domain: "Data", label: "Wipe data",    description: "Permanently erase all tenant data")
    ]

    // MARK: - Team (4)

    public static let team: [Capability] = [
        Capability(id: "team.invite",        domain: "Team", label: "Invite team members",  description: "Send invitations to new staff"),
        Capability(id: "team.suspend",       domain: "Team", label: "Suspend members",      description: "Temporarily disable a team member's access"),
        Capability(id: "team.change.role",   domain: "Team", label: "Change roles",         description: "Assign or change a member's role"),
        Capability(id: "team.view.payroll",  domain: "Team", label: "View payroll",         description: "See hourly rates and payroll summaries")
    ]

    // MARK: - Marketing (3)

    public static let marketing: [Capability] = [
        Capability(id: "marketing.campaign.create", domain: "Marketing", label: "Create campaigns",  description: "Draft new marketing campaigns"),
        Capability(id: "marketing.campaign.send",   domain: "Marketing", label: "Send campaigns",    description: "Launch campaigns to customer segments"),
        Capability(id: "marketing.segment.edit",    domain: "Marketing", label: "Edit segments",     description: "Define and modify customer segments")
    ]

    // MARK: - Danger (3)

    public static let danger: [Capability] = [
        Capability(id: "danger.feature.flag.override", domain: "Danger", label: "Override feature flags", description: "Enable or disable experimental features"),
        Capability(id: "danger.data.wipe",             domain: "Danger", label: "Wipe all data",          description: "Permanently destroy all tenant data"),
        Capability(id: "danger.tenant.delete",         domain: "Danger", label: "Delete tenant",          description: "Permanently delete the entire tenant account")
    ]

    // MARK: - Lookup helpers

    /// Returns the capability with the given id, or nil.
    public static func capability(for id: String) -> Capability? {
        all.first { $0.id == id }
    }

    /// Returns all capabilities grouped by domain in definition order.
    public static var byDomain: [(domain: String, capabilities: [Capability])] {
        let domains = CapabilityDomain.allCases.map(\.rawValue)
        return domains.compactMap { domain in
            let caps = all.filter { $0.domain == domain }
            return caps.isEmpty ? nil : (domain: domain, capabilities: caps)
        }
    }
}
