// DesignSystem/RTL/RTLPreviewCatalog.swift
//
// Pure catalog listing every screen / component that requires RTL preview
// coverage and smoke-test validation.
//
// Usage:
//   - RTLPreviewCatalog.screens contains every Screen entry.
//   - Tests assert RTLPreviewCatalog.screens.count >= 10.
//   - When adding a new screen, add a corresponding entry here and add an
//     RTL preview using .rtlPreview() in the view's #Preview block.
//
// §27 RTL layout checks

import Foundation

// MARK: - Screen entry

/// A catalog entry for a screen or component that must be validated in RTL layout.
public struct RTLCatalogEntry: Sendable, Identifiable {

    // MARK: Properties

    /// Unique identifier — typically the SwiftUI view type name.
    public let id: String

    /// Human-readable display name for preview catalogs and test reports.
    public let displayName: String

    /// Package or module the screen lives in.
    public let package: String

    /// True when an XCUITest smoke test in RTLSmokeTests.swift covers this screen.
    public let hasUITest: Bool

    /// True when the screen file contains an `.rtlPreview()` #Preview block.
    public let hasPreview: Bool

    /// Free-form notes — known RTL edge cases for this screen.
    public let notes: String

    // MARK: Init

    public init(
        id: String,
        displayName: String,
        package: String,
        hasUITest: Bool = false,
        hasPreview: Bool = false,
        notes: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.package = package
        self.hasUITest = hasUITest
        self.hasPreview = hasPreview
        self.notes = notes
    }
}

// MARK: - Catalog

/// Catalog of all screens / components requiring RTL layout validation.
///
/// Invariant enforced by tests: `screens.count >= 10`.
public enum RTLPreviewCatalog: Sendable {

    // MARK: - Screen list

    public static let screens: [RTLCatalogEntry] = [

        // ── Auth ──────────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "LoginFlowView",
            displayName: "Login Flow",
            package: "Auth",
            hasUITest: true,
            hasPreview: false,
            notes: "Server URL field + credential fields; step indicator uses .leading alignment. Glass panel must not over-extend in RTL."
        ),

        // ── Dashboard ─────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "DashboardView",
            displayName: "Dashboard Overview",
            package: "Dashboard",
            hasUITest: true,
            hasPreview: false,
            notes: "LazyVGrid tiles, RecentActivity widget, ClockInOutTile. Tile order should mirror in RTL."
        ),

        RTLCatalogEntry(
            id: "RecentActivityView",
            displayName: "Recent Activity Widget",
            package: "Dashboard",
            hasUITest: false,
            hasPreview: false,
            notes: "Activity rows with leading icon + trailing timestamp. Leading/trailing must swap in RTL."
        ),

        RTLCatalogEntry(
            id: "ClockInOutTileView",
            displayName: "Clock In/Out Tile",
            package: "Dashboard",
            hasUITest: false,
            hasPreview: false,
            notes: "Clock icon is non-directional (static). Duration text alignment must use .leading."
        ),

        // ── Tickets ───────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "TicketListView",
            displayName: "Ticket List",
            package: "Tickets",
            hasUITest: true,
            hasPreview: false,
            notes: "List rows with status badge (leading) + chevron (trailing). Swipe actions reverse in RTL."
        ),

        RTLCatalogEntry(
            id: "TicketDetailView",
            displayName: "Ticket Detail",
            package: "Tickets",
            hasUITest: false,
            hasPreview: false,
            notes: "Section headers, multi-line notes field, timeline activity list."
        ),

        // ── POS ───────────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "PosView",
            displayName: "POS Cart",
            package: "Pos",
            hasUITest: true,
            hasPreview: false,
            notes: "Product grid + cart column. Price labels (₪ / $) must use NumberFormatter.locale. Cart total row: price should be trailing in LTR, leading in RTL."
        ),

        RTLCatalogEntry(
            id: "CartRowView",
            displayName: "Cart Row",
            package: "Pos",
            hasUITest: false,
            hasPreview: false,
            notes: "Quantity stepper on leading side in LTR → trailing in RTL. Price on right in LTR → left in RTL."
        ),

        // ── Expenses ──────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "ExpenseDetailView",
            displayName: "Expense Detail",
            package: "Expenses",
            hasUITest: false,
            hasPreview: false,
            notes: "OCR pre-fill fields; receipt image; amount field. NumberFormatter.locale for currency display."
        ),

        // ── Customers ─────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "CustomerListView",
            displayName: "Customer List",
            package: "Customers",
            hasUITest: false,
            hasPreview: false,
            notes: "Avatar (leading) + name + LTV badge (trailing). Search bar text direction."
        ),

        // ── Inventory ─────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "InventoryListView",
            displayName: "Inventory List",
            package: "Inventory",
            hasUITest: false,
            hasPreview: false,
            notes: "Low-stock badge; price column must not clip Eastern Arabic numerals."
        ),

        // ── Invoices ──────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "InvoiceListView",
            displayName: "Invoice List",
            package: "Invoices",
            hasUITest: false,
            hasPreview: false,
            notes: "Amount column alignment; status badge; due-date label ordering."
        ),

        // ── Settings ──────────────────────────────────────────────────────────

        RTLCatalogEntry(
            id: "SettingsView",
            displayName: "Settings",
            package: "Settings",
            hasUITest: false,
            hasPreview: false,
            notes: "Toggle rows; section headers; grouped form layout."
        ),
    ]

    // MARK: - Helpers

    /// Screens that do NOT yet have an XCUITest smoke-test.
    public static var missingUITests: [RTLCatalogEntry] {
        screens.filter { !$0.hasUITest }
    }

    /// Screens that do NOT yet have an .rtlPreview() block.
    public static var missingPreviews: [RTLCatalogEntry] {
        screens.filter { !$0.hasPreview }
    }
}
