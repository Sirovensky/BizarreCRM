// Core/A11y/A11yDomainLabels.swift
//
// Shared, localization-ready accessibility label catalog grouped by CRM domain.
// Pure enum — no UI framework imports, safe for tests and SwiftUI previews.
//
// Rules (shared additive zone):
//   - Add new constants at the bottom of the relevant inner enum.
//   - Never rename or delete existing constants (key stability).
//   - Never pull in any framework dependency beyond Foundation.
//   - All strings are NSLocalizedString-backed so translators can localize them later.
//
// §26 A11y label catalog — domain labels

import Foundation

/// Domain-grouped accessibility label catalog for BizarreCRM.
///
/// Each constant is backed by `NSLocalizedString` so the string table can be
/// translated without changing call sites.
///
/// Usage:
/// ```swift
/// Text(A11yDomainLabels.Tickets.rowHint)
/// Image(systemName: "checkmark")
///     .accessibilityLabel(A11yDomainLabels.Invoices.paid)
/// ```
public enum A11yDomainLabels: Sendable {

    // MARK: - Tickets

    /// Accessibility labels for the Tickets domain.
    public enum Tickets: Sendable {
        public static let listTitle = NSLocalizedString(
            "a11y.tickets.listTitle",
            value: "Tickets",
            comment: "VoiceOver label for the Tickets list screen title"
        )
        public static let rowHint = NSLocalizedString(
            "a11y.tickets.rowHint",
            value: "Tap to open ticket details",
            comment: "VoiceOver hint on a ticket list row"
        )
        public static let newTicket = NSLocalizedString(
            "a11y.tickets.newTicket",
            value: "Create new ticket",
            comment: "VoiceOver label for the New Ticket button"
        )
        public static let statusLabel = NSLocalizedString(
            "a11y.tickets.statusLabel",
            value: "Ticket status",
            comment: "VoiceOver label prefix for a ticket status badge"
        )
        public static let priorityLabel = NSLocalizedString(
            "a11y.tickets.priorityLabel",
            value: "Priority",
            comment: "VoiceOver label prefix for a ticket priority badge"
        )
        public static let dueDateLabel = NSLocalizedString(
            "a11y.tickets.dueDateLabel",
            value: "Due date",
            comment: "VoiceOver label prefix for the ticket due-date field"
        )
        public static let assignedTo = NSLocalizedString(
            "a11y.tickets.assignedTo",
            value: "Assigned to",
            comment: "VoiceOver label prefix for the assigned technician field"
        )
        public static let deviceLabel = NSLocalizedString(
            "a11y.tickets.deviceLabel",
            value: "Device",
            comment: "VoiceOver label prefix for the device field on a ticket"
        )
        public static let notesLabel = NSLocalizedString(
            "a11y.tickets.notesLabel",
            value: "Notes",
            comment: "VoiceOver label for the ticket notes section"
        )
        public static let swipeActionsHint = NSLocalizedString(
            "a11y.tickets.swipeActionsHint",
            value: "Swipe left for more actions",
            comment: "VoiceOver hint for swipeable ticket rows"
        )
    }

    // MARK: - Customers

    /// Accessibility labels for the Customers domain.
    public enum Customers: Sendable {
        public static let listTitle = NSLocalizedString(
            "a11y.customers.listTitle",
            value: "Customers",
            comment: "VoiceOver label for the Customers list screen title"
        )
        public static let rowHint = NSLocalizedString(
            "a11y.customers.rowHint",
            value: "Tap to open customer details",
            comment: "VoiceOver hint on a customer list row"
        )
        public static let newCustomer = NSLocalizedString(
            "a11y.customers.newCustomer",
            value: "Create new customer",
            comment: "VoiceOver label for the New Customer button"
        )
        public static let phoneLabel = NSLocalizedString(
            "a11y.customers.phoneLabel",
            value: "Phone number",
            comment: "VoiceOver label prefix for a customer phone number"
        )
        public static let emailLabel = NSLocalizedString(
            "a11y.customers.emailLabel",
            value: "Email address",
            comment: "VoiceOver label prefix for a customer email address"
        )
        public static let openTicketsLabel = NSLocalizedString(
            "a11y.customers.openTicketsLabel",
            value: "Open tickets",
            comment: "VoiceOver label prefix for the open-ticket count on a customer row"
        )
        public static let lifetimeValueLabel = NSLocalizedString(
            "a11y.customers.lifetimeValueLabel",
            value: "Lifetime value",
            comment: "VoiceOver label prefix for the LTV field on a customer row"
        )
        public static let swipeActionsHint = NSLocalizedString(
            "a11y.customers.swipeActionsHint",
            value: "Swipe left for more actions",
            comment: "VoiceOver hint for swipeable customer rows"
        )
    }

    // MARK: - Invoices

    /// Accessibility labels for the Invoices domain.
    public enum Invoices: Sendable {
        public static let listTitle = NSLocalizedString(
            "a11y.invoices.listTitle",
            value: "Invoices",
            comment: "VoiceOver label for the Invoices list screen title"
        )
        public static let rowHint = NSLocalizedString(
            "a11y.invoices.rowHint",
            value: "Tap to view invoice",
            comment: "VoiceOver hint on an invoice list row"
        )
        public static let newInvoice = NSLocalizedString(
            "a11y.invoices.newInvoice",
            value: "Create new invoice",
            comment: "VoiceOver label for the New Invoice button"
        )
        public static let totalLabel = NSLocalizedString(
            "a11y.invoices.totalLabel",
            value: "Invoice total",
            comment: "VoiceOver label prefix for the invoice total amount"
        )
        public static let statusLabel = NSLocalizedString(
            "a11y.invoices.statusLabel",
            value: "Invoice status",
            comment: "VoiceOver label prefix for the invoice status badge"
        )
        public static let unpaid = NSLocalizedString(
            "a11y.invoices.unpaid",
            value: "Unpaid",
            comment: "VoiceOver label for the Unpaid invoice status"
        )
        public static let paid = NSLocalizedString(
            "a11y.invoices.paid",
            value: "Paid",
            comment: "VoiceOver label for the Paid invoice status"
        )
        public static let overdue = NSLocalizedString(
            "a11y.invoices.overdue",
            value: "Overdue",
            comment: "VoiceOver label for the Overdue invoice status"
        )
        public static let markAsPaid = NSLocalizedString(
            "a11y.invoices.markAsPaid",
            value: "Mark as paid",
            comment: "VoiceOver label for the mark-as-paid action"
        )
        public static let swipeActionsHint = NSLocalizedString(
            "a11y.invoices.swipeActionsHint",
            value: "Swipe left for more actions",
            comment: "VoiceOver hint for swipeable invoice rows"
        )
    }

    // MARK: - Inventory

    /// Accessibility labels for the Inventory domain.
    public enum Inventory: Sendable {
        public static let listTitle = NSLocalizedString(
            "a11y.inventory.listTitle",
            value: "Inventory",
            comment: "VoiceOver label for the Inventory list screen title"
        )
        public static let rowHint = NSLocalizedString(
            "a11y.inventory.rowHint",
            value: "Tap for item details",
            comment: "VoiceOver hint on an inventory item row"
        )
        public static let newItem = NSLocalizedString(
            "a11y.inventory.newItem",
            value: "Add new inventory item",
            comment: "VoiceOver label for the New Item button"
        )
        public static let skuLabel = NSLocalizedString(
            "a11y.inventory.skuLabel",
            value: "SKU",
            comment: "VoiceOver label prefix for the SKU field"
        )
        public static let stockLabel = NSLocalizedString(
            "a11y.inventory.stockLabel",
            value: "Stock quantity",
            comment: "VoiceOver label prefix for the stock quantity field"
        )
        public static let inStock = NSLocalizedString(
            "a11y.inventory.inStock",
            value: "In stock",
            comment: "VoiceOver label for an in-stock status"
        )
        public static let outOfStock = NSLocalizedString(
            "a11y.inventory.outOfStock",
            value: "Out of stock",
            comment: "VoiceOver label for an out-of-stock status"
        )
        public static let lowStockWarning = NSLocalizedString(
            "a11y.inventory.lowStockWarning",
            value: "Low stock warning",
            comment: "VoiceOver label for the low-stock warning badge"
        )
        public static let retailPriceLabel = NSLocalizedString(
            "a11y.inventory.retailPriceLabel",
            value: "Retail price",
            comment: "VoiceOver label prefix for the retail price field"
        )
        public static let adjustQuantity = NSLocalizedString(
            "a11y.inventory.adjustQuantity",
            value: "Adjust quantity",
            comment: "VoiceOver label for the quantity-adjustment stepper"
        )
        public static let swipeActionsHint = NSLocalizedString(
            "a11y.inventory.swipeActionsHint",
            value: "Swipe left for more actions",
            comment: "VoiceOver hint for swipeable inventory rows"
        )
    }

    // MARK: - POS (Point of Sale)

    /// Accessibility labels for the Point-of-Sale domain.
    public enum POS: Sendable {
        public static let screenTitle = NSLocalizedString(
            "a11y.pos.screenTitle",
            value: "Point of Sale",
            comment: "VoiceOver label for the POS screen title"
        )
        public static let cartLabel = NSLocalizedString(
            "a11y.pos.cartLabel",
            value: "Cart",
            comment: "VoiceOver label for the cart section in POS"
        )
        public static let cartItemHint = NSLocalizedString(
            "a11y.pos.cartItemHint",
            value: "Tap to edit, swipe to remove",
            comment: "VoiceOver hint for a cart line item"
        )
        public static let addToCart = NSLocalizedString(
            "a11y.pos.addToCart",
            value: "Add to cart",
            comment: "VoiceOver label for the Add to Cart button"
        )
        public static let removeFromCart = NSLocalizedString(
            "a11y.pos.removeFromCart",
            value: "Remove from cart",
            comment: "VoiceOver label for the Remove from Cart button"
        )
        public static let cartTotalLabel = NSLocalizedString(
            "a11y.pos.cartTotalLabel",
            value: "Cart total",
            comment: "VoiceOver label prefix for the cart total amount"
        )
        public static let checkoutButton = NSLocalizedString(
            "a11y.pos.checkoutButton",
            value: "Proceed to checkout",
            comment: "VoiceOver label for the Checkout button"
        )
        public static let paymentMethodLabel = NSLocalizedString(
            "a11y.pos.paymentMethodLabel",
            value: "Payment method",
            comment: "VoiceOver label prefix for payment method selector"
        )
        public static let discountLabel = NSLocalizedString(
            "a11y.pos.discountLabel",
            value: "Discount",
            comment: "VoiceOver label prefix for a cart discount"
        )
        public static let taxLabel = NSLocalizedString(
            "a11y.pos.taxLabel",
            value: "Tax",
            comment: "VoiceOver label prefix for the tax amount"
        )
        public static let voidSale = NSLocalizedString(
            "a11y.pos.voidSale",
            value: "Void sale",
            comment: "VoiceOver label for the Void Sale button"
        )
        public static let productSearchHint = NSLocalizedString(
            "a11y.pos.productSearchHint",
            value: "Search for products or scan a barcode",
            comment: "VoiceOver hint for the POS product search field"
        )
    }

    // MARK: - Navigation

    /// Accessibility labels for app-level navigation chrome.
    public enum Nav: Sendable {
        public static let dashboardTab = NSLocalizedString(
            "a11y.nav.dashboardTab",
            value: "Dashboard tab",
            comment: "VoiceOver label for the Dashboard tab bar item"
        )
        public static let ticketsTab = NSLocalizedString(
            "a11y.nav.ticketsTab",
            value: "Tickets tab",
            comment: "VoiceOver label for the Tickets tab bar item"
        )
        public static let customersTab = NSLocalizedString(
            "a11y.nav.customersTab",
            value: "Customers tab",
            comment: "VoiceOver label for the Customers tab bar item"
        )
        public static let inventoryTab = NSLocalizedString(
            "a11y.nav.inventoryTab",
            value: "Inventory tab",
            comment: "VoiceOver label for the Inventory tab bar item"
        )
        public static let invoicesTab = NSLocalizedString(
            "a11y.nav.invoicesTab",
            value: "Invoices tab",
            comment: "VoiceOver label for the Invoices tab bar item"
        )
        public static let posTab = NSLocalizedString(
            "a11y.nav.posTab",
            value: "Point of Sale tab",
            comment: "VoiceOver label for the POS tab bar item"
        )
        public static let settingsTab = NSLocalizedString(
            "a11y.nav.settingsTab",
            value: "Settings tab",
            comment: "VoiceOver label for the Settings tab bar item"
        )
        public static let backButton = NSLocalizedString(
            "a11y.nav.backButton",
            value: "Go back",
            comment: "VoiceOver label for a navigation back button"
        )
        public static let sidebarToggle = NSLocalizedString(
            "a11y.nav.sidebarToggle",
            value: "Toggle sidebar",
            comment: "VoiceOver label for the sidebar show/hide button (iPad)"
        )
        public static let commandPalette = NSLocalizedString(
            "a11y.nav.commandPalette",
            value: "Open command palette",
            comment: "VoiceOver label for the command palette trigger"
        )
        public static let closeSheet = NSLocalizedString(
            "a11y.nav.closeSheet",
            value: "Close sheet",
            comment: "VoiceOver label for a sheet dismiss button"
        )
    }
}
