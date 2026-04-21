// swift-tools-version: 6.0
// Core/Localization/Strings.swift
//
// Type-safe localization key catalog.  §27 i18n scaffold.
//
// Rules:
//   - Pure enum — no imports beyond Foundation.
//   - Keys match Localizable.strings exactly.
//   - NSLocalizedString uses default bundle (main bundle picks up the correct .lproj).
//   - Add new cases at the bottom of the relevant inner enum; never rename existing ones.
//
// Usage:
//   Text(L10n.Action.save)
//   Button(L10n.TicketStatus.intake) { ... }

import Foundation

/// Type-safe catalog of localized string keys for BizarreCRM.
public enum L10n: Sendable {

    // MARK: - Actions

    public enum Action: Sendable {
        public static let save          = NSLocalizedString("action.save",      comment: "Save button")
        public static let cancel        = NSLocalizedString("action.cancel",    comment: "Cancel button")
        public static let delete        = NSLocalizedString("action.delete",    comment: "Delete button")
        public static let edit          = NSLocalizedString("action.edit",      comment: "Edit button")
        public static let done          = NSLocalizedString("action.done",      comment: "Done button")
        public static let add           = NSLocalizedString("action.add",       comment: "Add button")
        public static let remove        = NSLocalizedString("action.remove",    comment: "Remove button")
        public static let close         = NSLocalizedString("action.close",     comment: "Close button")
        public static let retry         = NSLocalizedString("action.retry",     comment: "Retry button")
        public static let refresh       = NSLocalizedString("action.refresh",   comment: "Refresh button")
        public static let search        = NSLocalizedString("action.search",    comment: "Search button / placeholder")
        public static let filter        = NSLocalizedString("action.filter",    comment: "Filter button")
        public static let sort          = NSLocalizedString("action.sort",      comment: "Sort button")
        public static let share         = NSLocalizedString("action.share",     comment: "Share button")
        public static let export        = NSLocalizedString("action.export",    comment: "Export button")
        public static let `import`      = NSLocalizedString("action.import",    comment: "Import button")
        public static let print         = NSLocalizedString("action.print",     comment: "Print button")
        public static let scan          = NSLocalizedString("action.scan",      comment: "Scan button")
        public static let send          = NSLocalizedString("action.send",      comment: "Send button")
        public static let submit        = NSLocalizedString("action.submit",    comment: "Submit button")
        public static let confirm       = NSLocalizedString("action.confirm",   comment: "Confirm button")
        public static let archive       = NSLocalizedString("action.archive",   comment: "Archive button")
        public static let unarchive     = NSLocalizedString("action.unarchive", comment: "Unarchive button")
        public static let duplicate     = NSLocalizedString("action.duplicate", comment: "Duplicate button")
        public static let merge         = NSLocalizedString("action.merge",     comment: "Merge button")
        public static let convert       = NSLocalizedString("action.convert",   comment: "Convert button")
        public static let assign        = NSLocalizedString("action.assign",    comment: "Assign button")
        public static let signIn        = NSLocalizedString("action.signIn",    comment: "Sign-in button")
        public static let signOut       = NSLocalizedString("action.signOut",   comment: "Sign-out button")
        public static let `continue`    = NSLocalizedString("action.continue",  comment: "Continue button")
        public static let back          = NSLocalizedString("action.back",      comment: "Back button")
        public static let next          = NSLocalizedString("action.next",      comment: "Next button")
        public static let previous      = NSLocalizedString("action.previous",  comment: "Previous button")
        public static let apply         = NSLocalizedString("action.apply",     comment: "Apply button")
        public static let reset         = NSLocalizedString("action.reset",     comment: "Reset button")
    }

    // MARK: - Status

    public enum Status: Sendable {
        public static let loading       = NSLocalizedString("status.loading",   comment: "Loading indicator")
        public static let empty         = NSLocalizedString("status.empty",     comment: "Empty state")
        public static let error         = NSLocalizedString("status.error",     comment: "Error state")
        public static let offline       = NSLocalizedString("status.offline",   comment: "Offline banner")
        public static let online        = NSLocalizedString("status.online",    comment: "Online indicator")
        public static let syncing       = NSLocalizedString("status.syncing",   comment: "Syncing indicator")
        public static let synced        = NSLocalizedString("status.synced",    comment: "Synced indicator")
        public static let pending       = NSLocalizedString("status.pending",   comment: "Pending state")
        public static let failed        = NSLocalizedString("status.failed",    comment: "Failed state")
        public static let success       = NSLocalizedString("status.success",   comment: "Success state")
        public static let active        = NSLocalizedString("status.active",    comment: "Active state")
        public static let inactive      = NSLocalizedString("status.inactive",  comment: "Inactive state")
        public static let draft         = NSLocalizedString("status.draft",     comment: "Draft state")
        public static let archived      = NSLocalizedString("status.archived",  comment: "Archived state")
    }

    // MARK: - Field labels

    public enum Field: Sendable {
        public static let customerName  = NSLocalizedString("field.customer.name",  comment: "Customer name field")
        public static let firstName     = NSLocalizedString("field.first.name",     comment: "First name field")
        public static let lastName      = NSLocalizedString("field.last.name",      comment: "Last name field")
        public static let company       = NSLocalizedString("field.company",        comment: "Company field")
        public static let email         = NSLocalizedString("field.email",          comment: "Email field")
        public static let phone         = NSLocalizedString("field.phone",          comment: "Phone field")
        public static let address       = NSLocalizedString("field.address",        comment: "Address field")
        public static let city          = NSLocalizedString("field.city",           comment: "City field")
        public static let state         = NSLocalizedString("field.state",          comment: "State field")
        public static let zip           = NSLocalizedString("field.zip",            comment: "ZIP code field")
        public static let country       = NSLocalizedString("field.country",        comment: "Country field")
        public static let notes         = NSLocalizedString("field.notes",          comment: "Notes field")
        public static let description   = NSLocalizedString("field.description",    comment: "Description field")
        public static let title         = NSLocalizedString("field.title",          comment: "Title field")
        public static let amount        = NSLocalizedString("field.amount",         comment: "Amount field")
        public static let price         = NSLocalizedString("field.price",          comment: "Price field")
        public static let quantity      = NSLocalizedString("field.quantity",       comment: "Quantity field")
        public static let sku           = NSLocalizedString("field.sku",            comment: "SKU field")
        public static let barcode       = NSLocalizedString("field.barcode",        comment: "Barcode field")
        public static let serialNumber  = NSLocalizedString("field.serial.number",  comment: "Serial number field")
        public static let date          = NSLocalizedString("field.date",           comment: "Date field")
        public static let time          = NSLocalizedString("field.time",           comment: "Time field")
        public static let dueDate       = NSLocalizedString("field.due.date",       comment: "Due date field")
        public static let password      = NSLocalizedString("field.password",       comment: "Password field")
        public static let search        = NSLocalizedString("field.search",         comment: "Search field placeholder")
        public static let tax           = NSLocalizedString("field.tax",            comment: "Tax field")
        public static let discount      = NSLocalizedString("field.discount",       comment: "Discount field")
        public static let subtotal      = NSLocalizedString("field.subtotal",       comment: "Subtotal field")
        public static let total         = NSLocalizedString("field.total",          comment: "Total field")
    }

    // MARK: - Ticket status

    public enum TicketStatus: Sendable {
        public static let intake            = NSLocalizedString("ticket.status.intake",          comment: "Ticket status: intake")
        public static let diagnosing        = NSLocalizedString("ticket.status.diagnosing",      comment: "Ticket status: diagnosing")
        public static let waitingForParts   = NSLocalizedString("ticket.status.waitingForParts", comment: "Ticket status: waiting for parts")
        public static let inRepair          = NSLocalizedString("ticket.status.inRepair",        comment: "Ticket status: in repair")
        public static let repairComplete    = NSLocalizedString("ticket.status.repairComplete",  comment: "Ticket status: repair complete")
        public static let readyForPickup    = NSLocalizedString("ticket.status.readyForPickup",  comment: "Ticket status: ready for pickup")
        public static let pickedUp          = NSLocalizedString("ticket.status.pickedUp",        comment: "Ticket status: picked up")
        public static let cancelled         = NSLocalizedString("ticket.status.cancelled",       comment: "Ticket status: cancelled")
        public static let unrepairable      = NSLocalizedString("ticket.status.unrepairable",    comment: "Ticket status: unrepairable")
    }

    // MARK: - Ticket

    public enum Ticket: Sendable {
        public static let title         = NSLocalizedString("ticket.title",         comment: "Ticket entity singular")
        public static let listTitle     = NSLocalizedString("ticket.list.title",    comment: "Tickets list nav title")
        public static let new           = NSLocalizedString("ticket.new",           comment: "New ticket button/sheet title")
        public static let detailTitle   = NSLocalizedString("ticket.detail.title",  comment: "Ticket detail nav title")
        public static let device        = NSLocalizedString("ticket.device",        comment: "Ticket device field label")
        public static let technician    = NSLocalizedString("ticket.technician",    comment: "Ticket technician field label")
        public static let priority      = NSLocalizedString("ticket.priority",      comment: "Ticket priority field label")

        public enum Priority: Sendable {
            public static let low       = NSLocalizedString("ticket.priority.low",    comment: "Priority: low")
            public static let medium    = NSLocalizedString("ticket.priority.medium", comment: "Priority: medium")
            public static let high      = NSLocalizedString("ticket.priority.high",   comment: "Priority: high")
            public static let urgent    = NSLocalizedString("ticket.priority.urgent", comment: "Priority: urgent")
        }
    }

    // MARK: - Customer

    public enum Customer: Sendable {
        public static let title         = NSLocalizedString("customer.title",        comment: "Customer entity singular")
        public static let listTitle     = NSLocalizedString("customer.list.title",   comment: "Customers list nav title")
        public static let new           = NSLocalizedString("customer.new",          comment: "New customer button/sheet title")
        public static let detailTitle   = NSLocalizedString("customer.detail.title", comment: "Customer detail nav title")
        public static let ltv           = NSLocalizedString("customer.ltv",          comment: "Customer lifetime value label")
        public static let since         = NSLocalizedString("customer.since",        comment: "Customer since label")
    }

    // MARK: - Invoice

    public enum Invoice: Sendable {
        public static let title         = NSLocalizedString("invoice.title",        comment: "Invoice entity singular")
        public static let listTitle     = NSLocalizedString("invoice.list.title",   comment: "Invoices list nav title")
        public static let new           = NSLocalizedString("invoice.new",          comment: "New invoice button/sheet title")

        public enum InvoiceStatus: Sendable {
            public static let unpaid    = NSLocalizedString("invoice.status.unpaid",    comment: "Invoice status: unpaid")
            public static let paid      = NSLocalizedString("invoice.status.paid",      comment: "Invoice status: paid")
            public static let overdue   = NSLocalizedString("invoice.status.overdue",   comment: "Invoice status: overdue")
            public static let voided    = NSLocalizedString("invoice.status.voided",    comment: "Invoice status: voided")
            public static let refunded  = NSLocalizedString("invoice.status.refunded",  comment: "Invoice status: refunded")
        }
    }

    // MARK: - Inventory

    public enum Inventory: Sendable {
        public static let title         = NSLocalizedString("inventory.title",       comment: "Inventory nav title")
        public static let listTitle     = NSLocalizedString("inventory.list.title",  comment: "Inventory list nav title")
        public static let new           = NSLocalizedString("inventory.new",         comment: "New inventory item button")
        public static let inStock       = NSLocalizedString("inventory.inStock",     comment: "In stock label")
        public static let outOfStock    = NSLocalizedString("inventory.outOfStock",  comment: "Out of stock label")
        public static let lowStock      = NSLocalizedString("inventory.lowStock",    comment: "Low stock label")
    }

    // MARK: - Expense

    public enum Expense: Sendable {
        public static let title         = NSLocalizedString("expense.title",       comment: "Expense entity singular")
        public static let listTitle     = NSLocalizedString("expense.list.title",  comment: "Expenses list nav title")
        public static let new           = NSLocalizedString("expense.new",         comment: "New expense button/sheet title")
        public static let category      = NSLocalizedString("expense.category",    comment: "Expense category field")
        public static let receipt       = NSLocalizedString("expense.receipt",     comment: "Expense receipt label")
    }

    // MARK: - Appointment

    public enum Appointment: Sendable {
        public static let title         = NSLocalizedString("appointment.title",        comment: "Appointment entity singular")
        public static let listTitle     = NSLocalizedString("appointment.list.title",   comment: "Appointments list nav title")
        public static let new           = NSLocalizedString("appointment.new",          comment: "New appointment button")

        public enum AppointmentStatus: Sendable {
            public static let scheduled = NSLocalizedString("appointment.status.scheduled",  comment: "Appointment status: scheduled")
            public static let confirmed = NSLocalizedString("appointment.status.confirmed",  comment: "Appointment status: confirmed")
            public static let cancelled = NSLocalizedString("appointment.status.cancelled",  comment: "Appointment status: cancelled")
            public static let completed = NSLocalizedString("appointment.status.completed",  comment: "Appointment status: completed")
            public static let noShow    = NSLocalizedString("appointment.status.noShow",     comment: "Appointment status: no show")
        }
    }

    // MARK: - Employee

    public enum Employee: Sendable {
        public static let title         = NSLocalizedString("employee.title",       comment: "Employee entity singular")
        public static let listTitle     = NSLocalizedString("employee.list.title",  comment: "Employees list nav title")
        public static let clockIn       = NSLocalizedString("employee.clockIn",     comment: "Clock in action")
        public static let clockOut      = NSLocalizedString("employee.clockOut",    comment: "Clock out action")
        public static let clockedIn     = NSLocalizedString("employee.clockedIn",   comment: "Clocked-in status")
        public static let clockedOut    = NSLocalizedString("employee.clockedOut",  comment: "Clocked-out status")
    }

    // MARK: - Dashboard

    public enum Dashboard: Sendable {
        public static let title         = NSLocalizedString("dashboard.title",           comment: "Dashboard tab title")
        public static let revenueToday  = NSLocalizedString("dashboard.revenue.today",   comment: "Dashboard today revenue tile")
        public static let ticketsOpen   = NSLocalizedString("dashboard.tickets.open",    comment: "Dashboard open tickets tile")
        public static let recentActivity = NSLocalizedString("dashboard.recentActivity", comment: "Dashboard recent activity section")
    }

    // MARK: - Navigation

    public enum Nav: Sendable {
        public static let dashboard     = NSLocalizedString("nav.dashboard",    comment: "Dashboard tab label")
        public static let tickets       = NSLocalizedString("nav.tickets",      comment: "Tickets tab label")
        public static let customers     = NSLocalizedString("nav.customers",    comment: "Customers tab label")
        public static let inventory     = NSLocalizedString("nav.inventory",    comment: "Inventory tab label")
        public static let invoices      = NSLocalizedString("nav.invoices",     comment: "Invoices tab label")
        public static let expenses      = NSLocalizedString("nav.expenses",     comment: "Expenses tab label")
        public static let appointments  = NSLocalizedString("nav.appointments", comment: "Appointments tab label")
        public static let reports       = NSLocalizedString("nav.reports",      comment: "Reports tab label")
        public static let settings      = NSLocalizedString("nav.settings",     comment: "Settings tab label")
        public static let pos           = NSLocalizedString("nav.pos",          comment: "POS tab label")
    }

    // MARK: - Settings

    public enum Settings: Sendable {
        public static let title         = NSLocalizedString("settings.title",         comment: "Settings nav title")
        public static let account       = NSLocalizedString("settings.account",       comment: "Settings account row")
        public static let notifications = NSLocalizedString("settings.notifications", comment: "Settings notifications row")
        public static let appearance    = NSLocalizedString("settings.appearance",    comment: "Settings appearance row")
        public static let language      = NSLocalizedString("settings.language",      comment: "Settings language row")
        public static let security      = NSLocalizedString("settings.security",      comment: "Settings security row")
        public static let help          = NSLocalizedString("settings.help",          comment: "Settings help row")
        public static let about         = NSLocalizedString("settings.about",         comment: "Settings about row")
    }

    // MARK: - Errors / Alerts

    public enum Error: Sendable {
        public static let generic       = NSLocalizedString("error.generic",        comment: "Generic error message")
        public static let network       = NSLocalizedString("error.network",        comment: "Network error message")
        public static let notFound      = NSLocalizedString("error.notFound",       comment: "Not found error message")
        public static let unauthorized  = NSLocalizedString("error.unauthorized",   comment: "Unauthorized error message")
        public static let validation    = NSLocalizedString("error.validation",     comment: "Validation error message")
    }

    public enum Alert: Sendable {
        public static let deleteConfirmTitle    = NSLocalizedString("alert.deleteConfirm.title",   comment: "Delete confirm alert title")
        public static let deleteConfirmMessage  = NSLocalizedString("alert.deleteConfirm.message", comment: "Delete confirm alert body")
        public static let unsavedChangesTitle   = NSLocalizedString("alert.unsavedChanges.title",  comment: "Unsaved changes alert title")
        public static let unsavedChangesMessage = NSLocalizedString("alert.unsavedChanges.message",comment: "Unsaved changes alert body")
        public static let discard               = NSLocalizedString("alert.discard",               comment: "Discard unsaved changes button")
    }
}
