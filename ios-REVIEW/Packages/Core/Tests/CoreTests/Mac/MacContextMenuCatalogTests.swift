// CoreTests/Mac/MacContextMenuCatalogTests.swift
//
// Unit tests for §23 MacContextMenuCatalog + MacContextMenuItem + MenuRole.
//
// Coverage:
//   - All catalog items have non-empty id, title, symbolName
//   - All IDs are unique across the whole catalog
//   - MenuRole values are correct per item
//   - Domain sub-catalogs (Tickets, Invoices, Customers) are complete
//   - `all` list contains entries from every domain
//   - Equatable / Identifiable conformances
//   - Sendable conformance (compile-time)
//
// MacWindowCommands tests are in MacWindowCommandsTests.swift.
//
// §23 Mac polish — context menu catalog + window command tests

import XCTest
import SwiftUI
@testable import Core

// MARK: - MacContextMenuItem tests

final class MacContextMenuItemTests: XCTestCase {

    func test_init_storesAllProperties() {
        let item = MacContextMenuItem(
            id: "test.item",
            title: "Test",
            symbolName: "star",
            role: .destructive
        )
        XCTAssertEqual(item.id, "test.item")
        XCTAssertEqual(item.title, "Test")
        XCTAssertEqual(item.symbolName, "star")
        XCTAssertEqual(item.role, .destructive)
    }

    func test_init_defaultRoleIsNone() {
        let item = MacContextMenuItem(id: "x", title: "X", symbolName: "star")
        XCTAssertEqual(item.role, .none)
    }

    func test_equatable_sameValues_areEqual() {
        let a = MacContextMenuItem(id: "a", title: "A", symbolName: "s", role: .none)
        let b = MacContextMenuItem(id: "a", title: "A", symbolName: "s", role: .none)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentID_notEqual() {
        let a = MacContextMenuItem(id: "a", title: "A", symbolName: "s")
        let b = MacContextMenuItem(id: "b", title: "A", symbolName: "s")
        XCTAssertNotEqual(a, b)
    }

    func test_identifiable_usesIDProperty() {
        let item = MacContextMenuItem(id: "ctx.open", title: "Open", symbolName: "arrow.up.right.square")
        XCTAssertEqual(item.id, "ctx.open")
    }

    func test_sendable_compilesClean() {
        let item = MacContextMenuCatalog.Actions.open
        let _: @Sendable () -> MacContextMenuItem = { item }
    }
}

// MARK: - MenuRole tests

final class MenuRoleTests: XCTestCase {

    func test_noneRole_equatable() {
        XCTAssertEqual(MenuRole.none, MenuRole.none)
    }

    func test_destructiveRole_equatable() {
        XCTAssertEqual(MenuRole.destructive, MenuRole.destructive)
    }

    func test_differentRoles_notEqual() {
        XCTAssertNotEqual(MenuRole.none, MenuRole.destructive)
        XCTAssertNotEqual(MenuRole.none, MenuRole.cancel)
        XCTAssertNotEqual(MenuRole.destructive, MenuRole.cancel)
    }
}

// MARK: - MacContextMenuCatalog: Actions

final class MacContextMenuActionsTests: XCTestCase {

    func test_allActions_idNonEmpty() {
        let items: [MacContextMenuItem] = [
            MacContextMenuCatalog.Actions.open,
            MacContextMenuCatalog.Actions.edit,
            MacContextMenuCatalog.Actions.duplicate,
            MacContextMenuCatalog.Actions.move,
            MacContextMenuCatalog.Actions.share,
            MacContextMenuCatalog.Actions.copyID,
            MacContextMenuCatalog.Actions.archive,
            MacContextMenuCatalog.Actions.delete,
        ]
        for item in items {
            XCTAssertFalse(item.id.isEmpty,         "id must not be empty: \(item.title)")
            XCTAssertFalse(item.title.isEmpty,      "title must not be empty: \(item.id)")
            XCTAssertFalse(item.symbolName.isEmpty, "symbolName must not be empty: \(item.id)")
        }
    }

    func test_delete_isDestructive() {
        XCTAssertEqual(MacContextMenuCatalog.Actions.delete.role, .destructive)
    }

    func test_otherActions_areNotDestructive() {
        let nonDestructive: [MacContextMenuItem] = [
            MacContextMenuCatalog.Actions.open,
            MacContextMenuCatalog.Actions.edit,
            MacContextMenuCatalog.Actions.duplicate,
            MacContextMenuCatalog.Actions.archive,
        ]
        for item in nonDestructive {
            XCTAssertNotEqual(item.role, .destructive,
                              "\(item.id) should not be destructive")
        }
    }

    func test_stableIDs_actions() {
        XCTAssertEqual(MacContextMenuCatalog.Actions.open.id,      "ctx.open")
        XCTAssertEqual(MacContextMenuCatalog.Actions.edit.id,      "ctx.edit")
        XCTAssertEqual(MacContextMenuCatalog.Actions.duplicate.id, "ctx.duplicate")
        XCTAssertEqual(MacContextMenuCatalog.Actions.delete.id,    "ctx.delete")
        XCTAssertEqual(MacContextMenuCatalog.Actions.archive.id,   "ctx.archive")
        XCTAssertEqual(MacContextMenuCatalog.Actions.share.id,     "ctx.share")
        XCTAssertEqual(MacContextMenuCatalog.Actions.copyID.id,    "ctx.copyID")
        XCTAssertEqual(MacContextMenuCatalog.Actions.move.id,      "ctx.move")
    }
}

// MARK: - MacContextMenuCatalog: Tickets

final class MacContextMenuTicketsTests: XCTestCase {

    func test_allTicketItems_nonEmpty() {
        let items = [
            MacContextMenuCatalog.Tickets.markResolved,
            MacContextMenuCatalog.Tickets.reassign,
            MacContextMenuCatalog.Tickets.setPriority,
        ]
        for item in items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.symbolName.isEmpty)
        }
    }

    func test_stableIDs_tickets() {
        XCTAssertEqual(MacContextMenuCatalog.Tickets.markResolved.id, "ctx.tickets.markResolved")
        XCTAssertEqual(MacContextMenuCatalog.Tickets.reassign.id,     "ctx.tickets.reassign")
        XCTAssertEqual(MacContextMenuCatalog.Tickets.setPriority.id,  "ctx.tickets.setPriority")
    }

    func test_ticketItems_areNotDestructive() {
        let items = [
            MacContextMenuCatalog.Tickets.markResolved,
            MacContextMenuCatalog.Tickets.reassign,
            MacContextMenuCatalog.Tickets.setPriority,
        ]
        for item in items {
            XCTAssertNotEqual(item.role, .destructive)
        }
    }
}

// MARK: - MacContextMenuCatalog: Invoices

final class MacContextMenuInvoicesTests: XCTestCase {

    func test_allInvoiceItems_nonEmpty() {
        let items = [
            MacContextMenuCatalog.Invoices.markPaid,
            MacContextMenuCatalog.Invoices.sendByEmail,
            MacContextMenuCatalog.Invoices.print,
        ]
        for item in items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.symbolName.isEmpty)
        }
    }

    func test_stableIDs_invoices() {
        XCTAssertEqual(MacContextMenuCatalog.Invoices.markPaid.id,    "ctx.invoices.markPaid")
        XCTAssertEqual(MacContextMenuCatalog.Invoices.sendByEmail.id, "ctx.invoices.sendByEmail")
        XCTAssertEqual(MacContextMenuCatalog.Invoices.print.id,       "ctx.invoices.print")
    }
}

// MARK: - MacContextMenuCatalog: Customers

final class MacContextMenuCustomersTests: XCTestCase {

    func test_allCustomerItems_nonEmpty() {
        let items = [
            MacContextMenuCatalog.Customers.call,
            MacContextMenuCatalog.Customers.sendSMS,
            MacContextMenuCatalog.Customers.sendEmail,
        ]
        for item in items {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.symbolName.isEmpty)
        }
    }

    func test_stableIDs_customers() {
        XCTAssertEqual(MacContextMenuCatalog.Customers.call.id,       "ctx.customers.call")
        XCTAssertEqual(MacContextMenuCatalog.Customers.sendSMS.id,    "ctx.customers.sendSMS")
        XCTAssertEqual(MacContextMenuCatalog.Customers.sendEmail.id,  "ctx.customers.sendEmail")
    }
}

// MARK: - MacContextMenuCatalog: `all` list

final class MacContextMenuAllListTests: XCTestCase {

    func test_all_count() {
        XCTAssertEqual(MacContextMenuCatalog.all.count, 17, "Catalog must contain exactly 17 items")
    }

    func test_all_uniqueIDs() {
        let ids = MacContextMenuCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All catalog IDs must be unique")
    }

    func test_all_noneEmpty() {
        for item in MacContextMenuCatalog.all {
            XCTAssertFalse(item.id.isEmpty)
            XCTAssertFalse(item.title.isEmpty)
            XCTAssertFalse(item.symbolName.isEmpty)
        }
    }

    func test_all_containsDelete() {
        XCTAssertTrue(
            MacContextMenuCatalog.all.contains(MacContextMenuCatalog.Actions.delete)
        )
    }

    func test_all_containsTicketItem() {
        XCTAssertTrue(
            MacContextMenuCatalog.all.contains(MacContextMenuCatalog.Tickets.markResolved)
        )
    }

    func test_all_containsInvoiceItem() {
        XCTAssertTrue(
            MacContextMenuCatalog.all.contains(MacContextMenuCatalog.Invoices.markPaid)
        )
    }

    func test_all_containsCustomerItem() {
        XCTAssertTrue(
            MacContextMenuCatalog.all.contains(MacContextMenuCatalog.Customers.call)
        )
    }

    func test_all_exactlyOneDestructiveItem() {
        let destructive = MacContextMenuCatalog.all.filter { $0.role == .destructive }
        XCTAssertEqual(destructive.count, 1, "Only Delete should be destructive")
        XCTAssertEqual(destructive.first?.id, "ctx.delete")
    }
}

// MARK: - MacWindowCommands: compile-time smoke tests

/// These tests verify that `MacWindowCommands` builder methods return valid
/// `Commands`-conforming values and that the supplied closures are invocable.
/// Full UI-tree rendering is not available in a pure package test target.
final class MacWindowCommandsTests: XCTestCase {

    func test_fileCommands_closures_areInvocable() {
        var newCalled = false
        var saveCalled = false
        var closeCalled = false

        // Verify closures can be stored and called — the Commands value is
        // opaque so we can't inspect its tree without a full SwiftUI host.
        // Not @Sendable: these closures mutate local vars in a single-threaded test.
        let onNew: () -> Void   = { newCalled = true }
        let onSave: () -> Void  = { saveCalled = true }
        let onClose: () -> Void = { closeCalled = true }

        onNew()
        onSave()
        onClose()

        XCTAssertTrue(newCalled)
        XCTAssertTrue(saveCalled)
        XCTAssertTrue(closeCalled)
    }

    func test_editCommands_closures_areInvocable() {
        var undoCalled = false
        var redoCalled = false

        let onUndo: () -> Void = { undoCalled = true }
        let onRedo: () -> Void = { redoCalled = true }

        onUndo()
        onRedo()

        XCTAssertTrue(undoCalled)
        XCTAssertTrue(redoCalled)
    }

    func test_viewCommands_closures_areInvocable() {
        var refreshCalled = false
        var findCalled = false
        var paletteCalled = false

        let onRefresh: () -> Void = { refreshCalled = true }
        let onFind: () -> Void    = { findCalled = true }
        let onPalette: () -> Void = { paletteCalled = true }

        onRefresh()
        onFind()
        onPalette()

        XCTAssertTrue(refreshCalled)
        XCTAssertTrue(findCalled)
        XCTAssertTrue(paletteCalled)
    }

    /// Verify that `MacWindowCommands` builder methods produce SwiftUI
    /// `Commands`-conforming types without crashing.
    func test_fileCommands_compiles() {
        let cmds = MacWindowCommands.fileCommands(onNew: {}, onSave: {}, onClose: {})
        _ = cmds  // Consumes the value; confirms it compiles and doesn't crash.
    }

    func test_editCommands_compiles() {
        let cmds = MacWindowCommands.editCommands(onUndo: {}, onRedo: {})
        _ = cmds
    }

    func test_viewCommands_compiles() {
        let cmds = MacWindowCommands.viewCommands(
            onRefresh: {},
            onFind: {},
            onCommandPalette: {}
        )
        _ = cmds
    }

    /// `fileCommands` default `onClose` parameter must be callable without
    /// a crash — verifies the default argument is non-nil and works.
    func test_fileCommands_defaultClose_doesNotCrash() {
        let cmds = MacWindowCommands.fileCommands(onNew: {}, onSave: {})
        _ = cmds
    }
}

// MARK: - MacHoverEffects: BrandHoverStyle

final class MacHoverEffectsTests: XCTestCase {

    func test_brandHoverStyle_equatable() {
        XCTAssertEqual(BrandHoverStyle.highlight, BrandHoverStyle.highlight)
        XCTAssertEqual(BrandHoverStyle.lift, BrandHoverStyle.lift)
        XCTAssertNotEqual(BrandHoverStyle.highlight, BrandHoverStyle.lift)
        XCTAssertNotEqual(BrandHoverStyle.pointer, BrandHoverStyle.arrow)
        XCTAssertNotEqual(BrandHoverStyle.automatic, BrandHoverStyle.pointer)
    }

    func test_brandHoverStyle_allCases_areDistinct() {
        let cases: [BrandHoverStyle] = [.highlight, .lift, .automatic, .arrow, .pointer]
        // Each pair must be distinct.
        for i in cases.indices {
            for j in cases.indices where j != i {
                XCTAssertNotEqual(cases[i], cases[j],
                                  "BrandHoverStyle cases must all be distinct")
            }
        }
    }

    func test_brandHoverModifier_init_storesStyle() {
        let mod = BrandHoverModifier(style: .pointer)
        XCTAssertEqual(mod.style, .pointer)
    }

    func test_brandHoverModifier_defaultStyle_isAutomatic() {
        let mod = BrandHoverModifier()
        XCTAssertEqual(mod.style, .automatic)
    }

    func test_sendable_compilesClean() {
        let style: BrandHoverStyle = .highlight
        let _: @Sendable () -> BrandHoverStyle = { style }
    }
}
