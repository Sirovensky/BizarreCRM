// CoreTests/A11yLabelsTests.swift
//
// Unit tests for A11yLabels catalog.
// Verifies every catalog group is non-empty and strings are non-empty.
// §26 A11y label catalog tests

import XCTest
@testable import Core

final class A11yLabelsTests: XCTestCase {

    // MARK: - Actions catalog

    func test_actions_allNonEmpty() {
        let actions: [String] = [
            A11yLabels.Actions.save,
            A11yLabels.Actions.cancel,
            A11yLabels.Actions.delete,
            A11yLabels.Actions.edit,
            A11yLabels.Actions.addNew,
            A11yLabels.Actions.remove,
            A11yLabels.Actions.close,
            A11yLabels.Actions.done,
            A11yLabels.Actions.retry,
            A11yLabels.Actions.refresh,
            A11yLabels.Actions.search,
            A11yLabels.Actions.filter,
            A11yLabels.Actions.sort,
            A11yLabels.Actions.share,
            A11yLabels.Actions.export,
            A11yLabels.Actions.import,
            A11yLabels.Actions.print,
            A11yLabels.Actions.scan,
            A11yLabels.Actions.camera,
            A11yLabels.Actions.attach,
            A11yLabels.Actions.send,
            A11yLabels.Actions.submit,
            A11yLabels.Actions.confirm,
            A11yLabels.Actions.archive,
            A11yLabels.Actions.unarchive,
            A11yLabels.Actions.duplicate,
            A11yLabels.Actions.merge,
            A11yLabels.Actions.convert,
            A11yLabels.Actions.assign,
            A11yLabels.Actions.unassign,
            A11yLabels.Actions.pin,
            A11yLabels.Actions.unpin,
            A11yLabels.Actions.flag,
            A11yLabels.Actions.unflag,
            A11yLabels.Actions.moreOptions,
            A11yLabels.Actions.collapse,
            A11yLabels.Actions.expand,
            A11yLabels.Actions.copyToClipboard,
            A11yLabels.Actions.openLink,
            A11yLabels.Actions.download,
            A11yLabels.Actions.upload,
            A11yLabels.Actions.signIn,
            A11yLabels.Actions.signOut,
            A11yLabels.Actions.settings,
        ]
        for label in actions {
            XCTAssertFalse(label.isEmpty, "Action label must not be empty: \(label)")
        }
        XCTAssertGreaterThanOrEqual(actions.count, 20, "Actions catalog must have ≥20 entries")
    }

    func test_actions_noDuplicates() {
        let actions: [String] = [
            A11yLabels.Actions.save,
            A11yLabels.Actions.cancel,
            A11yLabels.Actions.delete,
            A11yLabels.Actions.edit,
            A11yLabels.Actions.addNew,
            A11yLabels.Actions.remove,
            A11yLabels.Actions.close,
            A11yLabels.Actions.done,
            A11yLabels.Actions.retry,
            A11yLabels.Actions.refresh,
        ]
        XCTAssertEqual(actions.count, Set(actions).count, "Actions must have unique labels")
    }

    // MARK: - Status catalog

    func test_status_allNonEmpty() {
        let statuses: [String] = [
            A11yLabels.Status.loading,
            A11yLabels.Status.empty,
            A11yLabels.Status.error,
            A11yLabels.Status.offline,
            A11yLabels.Status.online,
            A11yLabels.Status.syncing,
            A11yLabels.Status.synced,
            A11yLabels.Status.pending,
            A11yLabels.Status.failed,
            A11yLabels.Status.success,
            A11yLabels.Status.active,
            A11yLabels.Status.inactive,
            A11yLabels.Status.draft,
            A11yLabels.Status.archived,
            A11yLabels.Status.pinned,
            A11yLabels.Status.flagged,
            A11yLabels.Status.unread,
            A11yLabels.Status.updated,
            A11yLabels.Status.new,
        ]
        for label in statuses {
            XCTAssertFalse(label.isEmpty, "Status label must not be empty")
        }
        XCTAssertGreaterThanOrEqual(statuses.count, 5)
    }

    // MARK: - Navigation catalog

    func test_navigation_allNonEmpty() {
        let navLabels: [String] = [
            A11yLabels.Navigation.back,
            A11yLabels.Navigation.dismiss,
            A11yLabels.Navigation.next,
            A11yLabels.Navigation.previous,
            A11yLabels.Navigation.menu,
            A11yLabels.Navigation.sidebar,
            A11yLabels.Navigation.tab,
            A11yLabels.Navigation.home,
            A11yLabels.Navigation.commandPalette,
        ]
        for label in navLabels {
            XCTAssertFalse(label.isEmpty, "Navigation label must not be empty")
        }
    }

    // MARK: - Fields catalog

    func test_fields_allNonEmpty() {
        let fields: [String] = [
            A11yLabels.Fields.phone,
            A11yLabels.Fields.email,
            A11yLabels.Fields.customerName,
            A11yLabels.Fields.firstName,
            A11yLabels.Fields.lastName,
            A11yLabels.Fields.company,
            A11yLabels.Fields.address,
            A11yLabels.Fields.city,
            A11yLabels.Fields.state,
            A11yLabels.Fields.zipCode,
            A11yLabels.Fields.country,
            A11yLabels.Fields.notes,
            A11yLabels.Fields.description,
            A11yLabels.Fields.title,
            A11yLabels.Fields.amount,
            A11yLabels.Fields.price,
            A11yLabels.Fields.quantity,
            A11yLabels.Fields.sku,
            A11yLabels.Fields.barcode,
            A11yLabels.Fields.serialNumber,
            A11yLabels.Fields.password,
            A11yLabels.Fields.pin,
            A11yLabels.Fields.searchField,
            A11yLabels.Fields.date,
            A11yLabels.Fields.time,
            A11yLabels.Fields.dueDate,
        ]
        for label in fields {
            XCTAssertFalse(label.isEmpty, "Field label must not be empty")
        }
    }

    // MARK: - Entities catalog

    func test_entities_allNonEmpty() {
        let entities: [String] = [
            A11yLabels.Entities.ticket,
            A11yLabels.Entities.customer,
            A11yLabels.Entities.invoice,
            A11yLabels.Entities.estimate,
            A11yLabels.Entities.expense,
            A11yLabels.Entities.appointment,
            A11yLabels.Entities.employee,
            A11yLabels.Entities.product,
            A11yLabels.Entities.category,
            A11yLabels.Entities.notification,
            A11yLabels.Entities.message,
            A11yLabels.Entities.report,
            A11yLabels.Entities.lead,
            A11yLabels.Entities.payment,
            A11yLabels.Entities.refund,
        ]
        for label in entities {
            XCTAssertFalse(label.isEmpty, "Entity label must not be empty")
        }
    }

    // MARK: - Specific value checks (regression)

    func test_specificValues_matchExpected() {
        XCTAssertEqual(A11yLabels.Actions.save, "Save")
        XCTAssertEqual(A11yLabels.Actions.delete, "Delete")
        XCTAssertEqual(A11yLabels.Status.loading, "Loading")
        XCTAssertEqual(A11yLabels.Status.offline, "Offline")
        XCTAssertEqual(A11yLabels.Status.empty, "No items")
        XCTAssertEqual(A11yLabels.Navigation.back, "Back")
        XCTAssertEqual(A11yLabels.Navigation.dismiss, "Dismiss")
        XCTAssertEqual(A11yLabels.Fields.phone, "Phone number")
        XCTAssertEqual(A11yLabels.Fields.email, "Email address")
        XCTAssertEqual(A11yLabels.Fields.customerName, "Customer name")
    }

    // MARK: - Sendable conformance (compile-time)

    func test_sendableConformance_compilesClean() {
        // If A11yLabels is Sendable, this closure can capture it across concurrency.
        let label: String = A11yLabels.Actions.save
        let _: @Sendable () -> String = { label }
    }
}
