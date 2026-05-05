// swift-tools-version: 6.0
// Core/A11y/Labels.swift
//
// Centralized accessibility string catalog.
// Pure enum — no dependencies, no imports required.
// All strings are in English source; localization is handled at call sites
// via `String(localized:)` where needed.
//
// Rules (shared additive zone per ios/agent-ownership.md):
//   - Add new constants at the bottom of the relevant inner enum.
//   - Never rename or delete existing constants.
//   - Never pull in any framework dependency.
//
// §26 A11y label catalog

/// Centralized catalog of VoiceOver / accessibility label strings.
///
/// Usage:
/// ```swift
/// Button(A11yLabels.Actions.save) { save() }
///     .accessibilityLabel(A11yLabels.Actions.save)
/// Image(systemName: "trash")
///     .accessibilityLabel(A11yLabels.Actions.delete)
/// ```
public enum A11yLabels: Sendable {

    // MARK: - Actions

    /// Labels for interactive action controls (buttons, menu items, toolbar buttons).
    public enum Actions: Sendable {
        public static let save          = "Save"
        public static let cancel        = "Cancel"
        public static let delete        = "Delete"
        public static let edit          = "Edit"
        public static let addNew        = "Add new"
        public static let remove        = "Remove"
        public static let close         = "Close"
        public static let done          = "Done"
        public static let retry         = "Retry"
        public static let refresh       = "Refresh"
        public static let search        = "Search"
        public static let filter        = "Filter"
        public static let sort          = "Sort"
        public static let share         = "Share"
        public static let export        = "Export"
        public static let `import`      = "Import"
        public static let print         = "Print"
        public static let scan          = "Scan"
        public static let camera        = "Open camera"
        public static let attach        = "Attach file"
        public static let send          = "Send"
        public static let submit        = "Submit"
        public static let confirm       = "Confirm"
        public static let archive       = "Archive"
        public static let unarchive     = "Unarchive"
        public static let duplicate     = "Duplicate"
        public static let merge         = "Merge"
        public static let convert       = "Convert"
        public static let assign        = "Assign"
        public static let unassign      = "Unassign"
        public static let pin           = "Pin"
        public static let unpin         = "Unpin"
        public static let flag          = "Flag"
        public static let unflag        = "Unflag"
        public static let moreOptions   = "More options"
        public static let collapse      = "Collapse"
        public static let expand        = "Expand"
        public static let copyToClipboard = "Copy to clipboard"
        public static let openLink      = "Open link"
        public static let download      = "Download"
        public static let upload        = "Upload"
        public static let signIn        = "Sign in"
        public static let signOut       = "Sign out"
        public static let settings      = "Settings"
    }

    // MARK: - Status

    /// Labels that describe a current state or loading condition.
    public enum Status: Sendable {
        public static let loading       = "Loading"
        public static let empty         = "No items"
        public static let error         = "Error"
        public static let offline       = "Offline"
        public static let online        = "Online"
        public static let syncing       = "Syncing"
        public static let synced        = "Synced"
        public static let pending       = "Pending"
        public static let failed        = "Failed"
        public static let success       = "Success"
        public static let active        = "Active"
        public static let inactive      = "Inactive"
        public static let draft         = "Draft"
        public static let archived      = "Archived"
        public static let pinned        = "Pinned"
        public static let flagged       = "Flagged"
        public static let unread        = "Unread"
        public static let updated       = "Updated"
        public static let new           = "New"
    }

    // MARK: - Navigation

    /// Labels for navigation controls.
    public enum Navigation: Sendable {
        public static let back          = "Back"
        public static let dismiss       = "Dismiss"
        public static let next          = "Next"
        public static let previous      = "Previous"
        public static let menu          = "Menu"
        public static let sidebar       = "Sidebar"
        public static let tab           = "Tab"
        public static let home          = "Home"
        public static let commandPalette = "Open command palette"
    }

    // MARK: - Fields

    /// Labels for form field inputs.
    public enum Fields: Sendable {
        public static let phone         = "Phone number"
        public static let email         = "Email address"
        public static let customerName  = "Customer name"
        public static let firstName     = "First name"
        public static let lastName      = "Last name"
        public static let company       = "Company"
        public static let address       = "Address"
        public static let city          = "City"
        public static let state         = "State"
        public static let zipCode       = "ZIP code"
        public static let country       = "Country"
        public static let notes         = "Notes"
        public static let description   = "Description"
        public static let title         = "Title"
        public static let amount        = "Amount"
        public static let price         = "Price"
        public static let quantity      = "Quantity"
        public static let sku           = "SKU"
        public static let barcode       = "Barcode"
        public static let serialNumber  = "Serial number"
        public static let password      = "Password"
        public static let pin           = "PIN"
        public static let searchField   = "Search"
        public static let date          = "Date"
        public static let time          = "Time"
        public static let dueDate       = "Due date"
    }

    // MARK: - Entities

    /// Labels used to announce entity types and row descriptions.
    public enum Entities: Sendable {
        public static let ticket        = "Ticket"
        public static let customer      = "Customer"
        public static let invoice       = "Invoice"
        public static let estimate      = "Estimate"
        public static let expense       = "Expense"
        public static let appointment   = "Appointment"
        public static let employee      = "Employee"
        public static let product       = "Product"
        public static let category      = "Category"
        public static let notification  = "Notification"
        public static let message       = "Message"
        public static let report        = "Report"
        public static let lead          = "Lead"
        public static let payment       = "Payment"
        public static let refund        = "Refund"
    }

    // MARK: - Decorative / hidden

    /// Use `.accessibilityHidden(true)` on elements that pair with one of these
    /// to suppress them from VoiceOver when they are purely decorative.
    public enum Decorative: Sendable {
        /// Sentinel — apply `.accessibilityHidden(true)` to the element.
        public static let hidden        = ""
    }
}
