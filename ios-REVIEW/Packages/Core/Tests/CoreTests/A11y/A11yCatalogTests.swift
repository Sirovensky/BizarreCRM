// CoreTests/A11y/A11yCatalogTests.swift
//
// Unit tests for §26 A11y Label Catalog:
//   - A11yLabels     (domain-grouped, NSLocalizedString-backed labels)
//   - A11yRoleHints  (interaction hint strings)
//   - A11yLiveRegion (notification helper — compile-time + smoke)
//   - A11yTraitBundle (bundle composition + combinators)
//
// Coverage targets: non-empty string assertions, localization key stability,
// trait bundle composition, combinator immutability.
//
// §26 A11y label catalog — tests

import XCTest
import SwiftUI
@testable import Core

// MARK: - A11yLabels domain tests

final class A11yLabelsDomainTests: XCTestCase {

    // MARK: Tickets

    func test_tickets_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.Tickets.listTitle,
            A11yDomainLabels.Tickets.rowHint,
            A11yDomainLabels.Tickets.newTicket,
            A11yDomainLabels.Tickets.statusLabel,
            A11yDomainLabels.Tickets.priorityLabel,
            A11yDomainLabels.Tickets.dueDateLabel,
            A11yDomainLabels.Tickets.assignedTo,
            A11yDomainLabels.Tickets.deviceLabel,
            A11yDomainLabels.Tickets.notesLabel,
            A11yDomainLabels.Tickets.swipeActionsHint,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yDomainLabels.Tickets.\(value) must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "Tickets domain must have ≥5 labels")
    }

    func test_tickets_noDuplicates() {
        let values: [String] = [
            A11yDomainLabels.Tickets.listTitle,
            A11yDomainLabels.Tickets.rowHint,
            A11yDomainLabels.Tickets.newTicket,
            A11yDomainLabels.Tickets.statusLabel,
            A11yDomainLabels.Tickets.priorityLabel,
        ]
        XCTAssertEqual(values.count, Set(values).count, "Ticket labels must be unique")
    }

    // MARK: Customers

    func test_customers_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.Customers.listTitle,
            A11yDomainLabels.Customers.rowHint,
            A11yDomainLabels.Customers.newCustomer,
            A11yDomainLabels.Customers.phoneLabel,
            A11yDomainLabels.Customers.emailLabel,
            A11yDomainLabels.Customers.openTicketsLabel,
            A11yDomainLabels.Customers.lifetimeValueLabel,
            A11yDomainLabels.Customers.swipeActionsHint,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yDomainLabels.Customers must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "Customers domain must have ≥5 labels")
    }

    func test_customers_noDuplicates() {
        let values: [String] = [
            A11yDomainLabels.Customers.listTitle,
            A11yDomainLabels.Customers.rowHint,
            A11yDomainLabels.Customers.newCustomer,
            A11yDomainLabels.Customers.phoneLabel,
            A11yDomainLabels.Customers.emailLabel,
        ]
        XCTAssertEqual(values.count, Set(values).count, "Customer labels must be unique")
    }

    // MARK: Invoices

    func test_invoices_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.Invoices.listTitle,
            A11yDomainLabels.Invoices.rowHint,
            A11yDomainLabels.Invoices.newInvoice,
            A11yDomainLabels.Invoices.totalLabel,
            A11yDomainLabels.Invoices.statusLabel,
            A11yDomainLabels.Invoices.unpaid,
            A11yDomainLabels.Invoices.paid,
            A11yDomainLabels.Invoices.overdue,
            A11yDomainLabels.Invoices.markAsPaid,
            A11yDomainLabels.Invoices.swipeActionsHint,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yDomainLabels.Invoices must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "Invoices domain must have ≥5 labels")
    }

    // MARK: Inventory

    func test_inventory_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.Inventory.listTitle,
            A11yDomainLabels.Inventory.rowHint,
            A11yDomainLabels.Inventory.newItem,
            A11yDomainLabels.Inventory.skuLabel,
            A11yDomainLabels.Inventory.stockLabel,
            A11yDomainLabels.Inventory.inStock,
            A11yDomainLabels.Inventory.outOfStock,
            A11yDomainLabels.Inventory.lowStockWarning,
            A11yDomainLabels.Inventory.retailPriceLabel,
            A11yDomainLabels.Inventory.adjustQuantity,
            A11yDomainLabels.Inventory.swipeActionsHint,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yDomainLabels.Inventory must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "Inventory domain must have ≥5 labels")
    }

    // MARK: POS

    func test_pos_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.POS.screenTitle,
            A11yDomainLabels.POS.cartLabel,
            A11yDomainLabels.POS.cartItemHint,
            A11yDomainLabels.POS.addToCart,
            A11yDomainLabels.POS.removeFromCart,
            A11yDomainLabels.POS.cartTotalLabel,
            A11yDomainLabels.POS.checkoutButton,
            A11yDomainLabels.POS.paymentMethodLabel,
            A11yDomainLabels.POS.discountLabel,
            A11yDomainLabels.POS.taxLabel,
            A11yDomainLabels.POS.voidSale,
            A11yDomainLabels.POS.productSearchHint,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yDomainLabels.POS must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "POS domain must have ≥5 labels")
    }

    // MARK: Nav

    func test_nav_allNonEmpty() {
        let values: [String] = [
            A11yDomainLabels.Nav.dashboardTab,
            A11yDomainLabels.Nav.ticketsTab,
            A11yDomainLabels.Nav.customersTab,
            A11yDomainLabels.Nav.inventoryTab,
            A11yDomainLabels.Nav.invoicesTab,
            A11yDomainLabels.Nav.posTab,
            A11yDomainLabels.Nav.settingsTab,
            A11yDomainLabels.Nav.backButton,
            A11yDomainLabels.Nav.sidebarToggle,
            A11yDomainLabels.Nav.commandPalette,
            A11yDomainLabels.Nav.closeSheet,
        ]
        for value in values {
            XCTAssertFalse(value.isEmpty, "A11yLabels.Nav must not be empty")
        }
        XCTAssertGreaterThanOrEqual(values.count, 5, "Nav domain must have ≥5 labels")
    }

    // MARK: Localization key stability (regression)

    func test_localizationKeys_areStable() {
        // Verify the English fallback values — these must never change silently.
        // When there is no .strings file the NSLocalizedString returns its `value:`.
        XCTAssertEqual(A11yDomainLabels.Tickets.listTitle,      "Tickets")
        XCTAssertEqual(A11yDomainLabels.Tickets.rowHint,        "Tap to open ticket details")
        XCTAssertEqual(A11yDomainLabels.Tickets.newTicket,      "Create new ticket")
        XCTAssertEqual(A11yDomainLabels.Customers.listTitle,    "Customers")
        XCTAssertEqual(A11yDomainLabels.Customers.rowHint,      "Tap to open customer details")
        XCTAssertEqual(A11yDomainLabels.Invoices.listTitle,     "Invoices")
        XCTAssertEqual(A11yDomainLabels.Invoices.paid,          "Paid")
        XCTAssertEqual(A11yDomainLabels.Invoices.overdue,       "Overdue")
        XCTAssertEqual(A11yDomainLabels.Inventory.inStock,      "In stock")
        XCTAssertEqual(A11yDomainLabels.Inventory.outOfStock,   "Out of stock")
        XCTAssertEqual(A11yDomainLabels.POS.checkoutButton,     "Proceed to checkout")
        XCTAssertEqual(A11yDomainLabels.Nav.backButton,         "Go back")
        XCTAssertEqual(A11yDomainLabels.Nav.commandPalette,     "Open command palette")
    }

    // MARK: Sendable conformance (compile-time)

    func test_sendable_compilesClean() {
        let label: String = A11yDomainLabels.Tickets.listTitle
        let _: @Sendable () -> String = { label }
    }
}

// MARK: - A11yRoleHints tests

final class A11yRoleHintsTests: XCTestCase {

    func test_allHints_nonEmpty() {
        let hints: [String] = [
            A11yRoleHints.doubleTapToOpen,
            A11yRoleHints.doubleTapToSelect,
            A11yRoleHints.doubleTapToToggle,
            A11yRoleHints.doubleTapToEdit,
            A11yRoleHints.doubleTapToDelete,
            A11yRoleHints.doubleTapToConfirm,
            A11yRoleHints.swipeLeftForActions,
            A11yRoleHints.swipeRightToMarkDone,
            A11yRoleHints.swipeToAdjustValue,
            A11yRoleHints.longPressForOptions,
            A11yRoleHints.navigateWithTabBar,
            A11yRoleHints.dragToReorder,
            A11yRoleHints.doubleTapToExpand,
            A11yRoleHints.doubleTapToCollapse,
            A11yRoleHints.doubleTapToSearch,
            A11yRoleHints.pointCameraToScan,
            A11yRoleHints.contentLoading,
        ]
        for hint in hints {
            XCTAssertFalse(hint.isEmpty, "A11yRoleHints constant must not be empty")
        }
        XCTAssertGreaterThanOrEqual(hints.count, 10, "Role hints must have ≥10 entries")
    }

    func test_allHints_noDuplicates() {
        let hints: [String] = [
            A11yRoleHints.doubleTapToOpen,
            A11yRoleHints.doubleTapToSelect,
            A11yRoleHints.doubleTapToToggle,
            A11yRoleHints.doubleTapToEdit,
            A11yRoleHints.doubleTapToDelete,
            A11yRoleHints.swipeLeftForActions,
            A11yRoleHints.swipeRightToMarkDone,
            A11yRoleHints.longPressForOptions,
            A11yRoleHints.dragToReorder,
            A11yRoleHints.doubleTapToExpand,
        ]
        XCTAssertEqual(hints.count, Set(hints).count, "Role hints must be unique")
    }

    func test_hintKeyStability() {
        XCTAssertEqual(A11yRoleHints.doubleTapToOpen,      "Double-tap to open")
        XCTAssertEqual(A11yRoleHints.swipeLeftForActions,  "Swipe left for more actions")
        XCTAssertEqual(A11yRoleHints.longPressForOptions,  "Touch and hold for options")
        XCTAssertEqual(A11yRoleHints.dragToReorder,        "Drag to reorder")
    }

    func test_sendable_compilesClean() {
        let hint: String = A11yRoleHints.doubleTapToOpen
        let _: @Sendable () -> String = { hint }
    }
}

// MARK: - A11yLiveRegion tests

final class A11yLiveRegionTests: XCTestCase {

    // A11yLiveRegion wraps UIKit which isn't available in a macOS test runner.
    // These tests verify the non-UIKit code paths (guard !isEmpty, Task creation)
    // and that the API compiles correctly.

    @MainActor
    func test_announce_emptyString_doesNotCrash() {
        // Should return silently without crashing or posting a notification.
        A11yLiveRegion.announce("")
    }

    @MainActor
    func test_announce_nonEmptyString_doesNotCrash() {
        // On non-UIKit platforms this is a no-op; on iOS it posts a notification.
        A11yLiveRegion.announce("Test announcement")
    }

    @MainActor
    func test_announceWithDelay_doesNotCrash() {
        A11yLiveRegion.announce("Delayed announcement", afterDelay: 0.01)
    }

    @MainActor
    func test_announceSaved_formatsEntityName() {
        // We can't capture the UIAccessibility argument, but we verify the
        // helper compiles and doesn't crash for a variety of entity names.
        A11yLiveRegion.announceSaved(entityName: "Ticket")
        A11yLiveRegion.announceSaved(entityName: "Invoice")
        A11yLiveRegion.announceSaved(entityName: "Customer")
    }

    @MainActor
    func test_announceDeleted_formatsEntityName() {
        A11yLiveRegion.announceDeleted(entityName: "Ticket")
        A11yLiveRegion.announceDeleted(entityName: "")  // empty — should not crash
    }

    @MainActor
    func test_announceError_nonEmpty_doesNotCrash() {
        A11yLiveRegion.announceError("Network connection lost")
    }

    @MainActor
    func test_announceError_empty_doesNotCrash() {
        A11yLiveRegion.announceError("")
    }

    @MainActor
    func test_layoutChanged_doesNotCrash() {
        A11yLiveRegion.layoutChanged()
        A11yLiveRegion.layoutChanged(focusOn: nil)
    }

    @MainActor
    func test_screenChanged_doesNotCrash() {
        A11yLiveRegion.screenChanged()
        A11yLiveRegion.screenChanged(focusOn: nil)
    }
}

// MARK: - A11yTraitBundle tests

final class A11yTraitBundleTests: XCTestCase {

    // MARK: Basic construction

    func test_init_storesAllProperties() {
        let bundle = A11yTraitBundle(
            label: "Open ticket",
            hint: "Double-tap to open",
            traits: [.isButton]
        )
        XCTAssertEqual(bundle.label, "Open ticket")
        XCTAssertEqual(bundle.hint,  "Double-tap to open")
        XCTAssertEqual(bundle.traits, [.isButton])
    }

    func test_init_defaultHintIsEmpty() {
        let bundle = A11yTraitBundle(label: "My label")
        XCTAssertEqual(bundle.hint, "")
    }

    func test_init_defaultTraitsIsStaticText() {
        let bundle = A11yTraitBundle(label: "My label")
        XCTAssertEqual(bundle.traits, .isStaticText)
    }

    // MARK: Factory helpers

    func test_listRow_usesButtonTraits() {
        let bundle = A11yTraitBundle.listRow(label: "Invoice row")
        XCTAssertEqual(bundle.traits, [.isButton])
        XCTAssertFalse(bundle.hint.isEmpty, "listRow hint must not be empty")
        XCTAssertEqual(bundle.label, "Invoice row")
    }

    func test_listRow_customHint() {
        let bundle = A11yTraitBundle.listRow(label: "Ticket", hint: "Custom hint")
        XCTAssertEqual(bundle.hint, "Custom hint")
    }

    func test_button_usesButtonTraits() {
        let bundle = A11yTraitBundle.button(label: "Save")
        XCTAssertEqual(bundle.traits, [.isButton])
        XCTAssertEqual(bundle.label, "Save")
    }

    func test_header_usesHeaderTraits() {
        let bundle = A11yTraitBundle.header(label: "Tickets")
        XCTAssertEqual(bundle.traits, [.isHeader])
        XCTAssertEqual(bundle.hint, "")
    }

    func test_link_usesLinkTraits() {
        let bundle = A11yTraitBundle.link(label: "Open website")
        XCTAssertEqual(bundle.traits, [.isLink])
        XCTAssertFalse(bundle.hint.isEmpty, "link hint must not be empty")
    }

    func test_badge_usesStaticTextTraits() {
        let bundle = A11yTraitBundle.badge(label: "Overdue")
        XCTAssertEqual(bundle.traits, .isStaticText)
    }

    func test_image_usesImageTraits() {
        let bundle = A11yTraitBundle.image(label: "Company logo")
        XCTAssertEqual(bundle.traits, [.isImage])
    }

    // MARK: Combinators — immutability

    func test_withLabel_returnsNewBundle() {
        let original = A11yTraitBundle(label: "Old", hint: "Hint", traits: [.isButton])
        let updated  = original.withLabel("New")

        // original is unchanged
        XCTAssertEqual(original.label, "Old")
        // new bundle reflects the change
        XCTAssertEqual(updated.label,  "New")
        // other fields are preserved
        XCTAssertEqual(updated.hint,   "Hint")
        XCTAssertEqual(updated.traits, [.isButton])
    }

    func test_withHint_returnsNewBundle() {
        let original = A11yTraitBundle(label: "Label", hint: "Old hint")
        let updated  = original.withHint("New hint")

        XCTAssertEqual(original.hint, "Old hint")
        XCTAssertEqual(updated.hint,  "New hint")
        XCTAssertEqual(updated.label, "Label")
    }

    func test_addingTraits_mergesTraits() {
        let base    = A11yTraitBundle(label: "Label", traits: [.isButton])
        let updated = base.addingTraits([.isSelected])

        // Original is unchanged
        XCTAssertEqual(base.traits, [.isButton])
        // Updated has both
        XCTAssertTrue(updated.traits.contains(.isButton))
        XCTAssertTrue(updated.traits.contains(.isSelected))
    }

    func test_addingTraits_idempotent() {
        let bundle  = A11yTraitBundle(label: "Label", traits: [.isButton])
        let doubled = bundle.addingTraits([.isButton])
        XCTAssertEqual(doubled.traits, bundle.traits, "Adding same trait twice is idempotent")
    }

    // MARK: Equatable

    func test_equatable_sameValues_areEqual() {
        let a = A11yTraitBundle(label: "X", hint: "Y", traits: [.isButton])
        let b = A11yTraitBundle(label: "X", hint: "Y", traits: [.isButton])
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentLabel_notEqual() {
        let a = A11yTraitBundle(label: "A", hint: "H")
        let b = A11yTraitBundle(label: "B", hint: "H")
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentHint_notEqual() {
        let a = A11yTraitBundle(label: "L", hint: "A")
        let b = A11yTraitBundle(label: "L", hint: "B")
        XCTAssertNotEqual(a, b)
    }

    // MARK: Composition with catalog

    func test_composedWithCatalog_ticketRow() {
        let bundle = A11yTraitBundle.listRow(
            label: A11yDomainLabels.Tickets.listTitle,
            hint:  A11yRoleHints.swipeLeftForActions
        )
        XCTAssertFalse(bundle.label.isEmpty)
        XCTAssertFalse(bundle.hint.isEmpty)
        XCTAssertEqual(bundle.traits, [.isButton])
    }

    func test_composedWithCatalog_invoiceBadge() {
        let bundle = A11yTraitBundle.badge(label: A11yDomainLabels.Invoices.overdue)
        XCTAssertEqual(bundle.label, "Overdue")
        XCTAssertEqual(bundle.traits, .isStaticText)
    }

    func test_composedWithCatalog_navButton() {
        let bundle = A11yTraitBundle.button(label: A11yDomainLabels.Nav.backButton)
        XCTAssertEqual(bundle.label, "Go back")
        XCTAssertEqual(bundle.traits, [.isButton])
    }

    // MARK: Sendable conformance (compile-time)

    func test_sendable_compilesClean() {
        let bundle = A11yTraitBundle(label: "Test")
        let _: @Sendable () -> A11yTraitBundle = { bundle }
    }
}
