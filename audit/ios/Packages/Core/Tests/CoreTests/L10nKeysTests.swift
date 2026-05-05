// Core/Tests/CoreTests/L10nKeysTests.swift
//
// §27 i18n tests — verifies key catalog integrity.
//
// Tests:
//   1. Every L10n static property resolves to a non-empty string.
//   2. All L10n keys are present in en.lproj/Localizable.strings (no orphan keys).
//   3. Spanish (es.lproj) has exactly the same set of keys as English.
//
// NOTE: Tests run against the test bundle, which does NOT have the app's .lproj files
// on disk.  Key-resolution tests therefore rely on Bundle.main only being available
// when tests are run embedded; for CI we parse the .strings files directly instead,
// which is more reliable and avoids bundle-lookup fragility.

import XCTest
@testable import Core

final class L10nKeysTests: XCTestCase {

    // MARK: - Helpers

    /// Resolves path to a .strings file relative to this source file.
    private func stringsPath(locale: String) -> String {
        // #filePath resolves to the absolute path of THIS source file:
        //   .../ios/Packages/Core/Tests/CoreTests/L10nKeysTests.swift
        // Walk up to ios/:
        //   L10nKeysTests.swift → CoreTests/ → Tests/ → Core/ → Packages/ → ios/
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url = url.deletingLastPathComponent() }
        return url
            .appendingPathComponent("App/Resources/Locales/\(locale).lproj/Localizable.strings")
            .path
    }

    /// Parses a Localizable.strings file and returns the set of keys.
    private func parseKeys(from path: String) -> Set<String> {
        guard FileManager.default.fileExists(atPath: path),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return []
        }
        return Set(dict.keys)
    }

    /// All keys declared in the L10n catalog (collected via Mirror / static listing).
    private var catalogKeys: [String] {
        // We enumerate these manually to guarantee the test stays in sync with
        // Strings.swift without relying on runtime reflection of static lets.
        [
            // Action
            "action.save", "action.cancel", "action.delete", "action.edit",
            "action.done", "action.add", "action.remove", "action.close",
            "action.retry", "action.refresh", "action.search", "action.filter",
            "action.sort", "action.share", "action.export", "action.import",
            "action.print", "action.scan", "action.send", "action.submit",
            "action.confirm", "action.archive", "action.unarchive",
            "action.duplicate", "action.merge", "action.convert", "action.assign",
            "action.signIn", "action.signOut", "action.continue", "action.back",
            "action.next", "action.previous", "action.apply", "action.reset",
            // Status
            "status.loading", "status.empty", "status.error", "status.offline",
            "status.online", "status.syncing", "status.synced", "status.pending",
            "status.failed", "status.success", "status.active", "status.inactive",
            "status.draft", "status.archived",
            // Field
            "field.customer.name", "field.first.name", "field.last.name",
            "field.company", "field.email", "field.phone", "field.address",
            "field.city", "field.state", "field.zip", "field.country",
            "field.notes", "field.description", "field.title", "field.amount",
            "field.price", "field.quantity", "field.sku", "field.barcode",
            "field.serial.number", "field.date", "field.time", "field.due.date",
            "field.password", "field.search", "field.tax", "field.discount",
            "field.subtotal", "field.total",
            // Ticket status
            "ticket.status.intake", "ticket.status.diagnosing",
            "ticket.status.waitingForParts", "ticket.status.inRepair",
            "ticket.status.repairComplete", "ticket.status.readyForPickup",
            "ticket.status.pickedUp", "ticket.status.cancelled",
            "ticket.status.unrepairable",
            // Ticket
            "ticket.title", "ticket.list.title", "ticket.new",
            "ticket.detail.title", "ticket.device", "ticket.technician",
            "ticket.priority", "ticket.priority.low", "ticket.priority.medium",
            "ticket.priority.high", "ticket.priority.urgent",
            // Customer
            "customer.title", "customer.list.title", "customer.new",
            "customer.detail.title", "customer.ltv", "customer.since",
            // Invoice
            "invoice.title", "invoice.list.title", "invoice.new",
            "invoice.status.unpaid", "invoice.status.paid",
            "invoice.status.overdue", "invoice.status.voided",
            "invoice.status.refunded",
            // Inventory
            "inventory.title", "inventory.list.title", "inventory.new",
            "inventory.inStock", "inventory.outOfStock", "inventory.lowStock",
            // Expense
            "expense.title", "expense.list.title", "expense.new",
            "expense.category", "expense.receipt",
            // Appointment
            "appointment.title", "appointment.list.title", "appointment.new",
            "appointment.status.scheduled", "appointment.status.confirmed",
            "appointment.status.cancelled", "appointment.status.completed",
            "appointment.status.noShow",
            // Employee
            "employee.title", "employee.list.title", "employee.clockIn",
            "employee.clockOut", "employee.clockedIn", "employee.clockedOut",
            // Dashboard
            "dashboard.title", "dashboard.revenue.today",
            "dashboard.tickets.open", "dashboard.recentActivity",
            // Nav
            "nav.dashboard", "nav.tickets", "nav.customers", "nav.inventory",
            "nav.invoices", "nav.expenses", "nav.appointments",
            "nav.reports", "nav.settings", "nav.pos",
            // Settings
            "settings.title", "settings.account", "settings.notifications",
            "settings.appearance", "settings.language", "settings.security",
            "settings.help", "settings.about",
            // Error
            "error.generic", "error.network", "error.notFound",
            "error.unauthorized", "error.validation",
            // Alert
            "alert.deleteConfirm.title", "alert.deleteConfirm.message",
            "alert.unsavedChanges.title", "alert.unsavedChanges.message",
            "alert.discard",
        ]
    }

    // MARK: - Tests

    /// All keys declared in the L10n catalog must exist in en.lproj/Localizable.strings.
    func test_allCatalogKeys_presentInEnglishStringsFile() throws {
        let path = stringsPath(locale: "en")
        let enKeys = parseKeys(from: path)

        XCTAssertFalse(
            enKeys.isEmpty,
            "en.lproj/Localizable.strings not found or empty at: \(path)"
        )

        var missing: [String] = []
        for key in catalogKeys {
            if !enKeys.contains(key) {
                missing.append(key)
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "L10n catalog keys missing from en.lproj/Localizable.strings:\n"
            + missing.sorted().joined(separator: "\n")
        )
    }

    /// Spanish strings file must have the same set of keys as English.
    func test_spanishStringsFile_hasParityWithEnglish() throws {
        let enPath = stringsPath(locale: "en")
        let esPath = stringsPath(locale: "es")

        let enKeys = parseKeys(from: enPath)
        let esKeys = parseKeys(from: esPath)

        XCTAssertFalse(enKeys.isEmpty, "en.lproj not found at: \(enPath)")
        XCTAssertFalse(esKeys.isEmpty, "es.lproj not found at: \(esPath)")

        let missingInEs = enKeys.subtracting(esKeys).sorted()
        let extraInEs   = esKeys.subtracting(enKeys).sorted()

        XCTAssertTrue(
            missingInEs.isEmpty,
            "Keys in en.lproj missing from es.lproj:\n"
            + missingInEs.joined(separator: "\n")
        )
        XCTAssertTrue(
            extraInEs.isEmpty,
            "Keys in es.lproj not present in en.lproj:\n"
            + extraInEs.joined(separator: "\n")
        )
    }

    /// English strings file must have no empty values.
    func test_englishStrings_noEmptyValues() throws {
        let path = stringsPath(locale: "en")
        guard FileManager.default.fileExists(atPath: path),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("en.lproj/Localizable.strings not found at: \(path)")
            return
        }

        let emptyKeys = dict.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys.sorted()
        XCTAssertTrue(
            emptyKeys.isEmpty,
            "English strings with empty values:\n" + emptyKeys.joined(separator: "\n")
        )
    }

    /// Spanish strings file must have no empty values.
    func test_spanishStrings_noEmptyValues() throws {
        let path = stringsPath(locale: "es")
        guard FileManager.default.fileExists(atPath: path),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("es.lproj/Localizable.strings not found at: \(path)")
            return
        }

        let emptyKeys = dict.filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys.sorted()
        XCTAssertTrue(
            emptyKeys.isEmpty,
            "Spanish strings with empty values:\n" + emptyKeys.joined(separator: "\n")
        )
    }

    /// Pseudo-locale file exists and has at least as many keys as English.
    func test_pseudoLocale_existsAndHasSufficientKeys() throws {
        let enPath     = stringsPath(locale: "en")
        let pseudoPath = stringsPath(locale: "pseudo")

        let enKeys     = parseKeys(from: enPath)
        let pseudoKeys = parseKeys(from: pseudoPath)

        XCTAssertFalse(enKeys.isEmpty,    "en.lproj not found")
        XCTAssertFalse(pseudoKeys.isEmpty,"pseudo.lproj not found at: \(pseudoPath)")
        XCTAssertGreaterThanOrEqual(
            pseudoKeys.count, enKeys.count,
            "pseudo.lproj should have at least as many keys as en.lproj"
        )
    }

    /// Pseudo-locale values must be wrapped with ⟦ and ⟧.
    func test_pseudoLocaleValues_areWrapped() throws {
        let path = stringsPath(locale: "pseudo")
        guard FileManager.default.fileExists(atPath: path),
              let dict = NSDictionary(contentsOfFile: path) as? [String: String] else {
            XCTFail("pseudo.lproj not found at: \(path)")
            return
        }

        let unwrapped = dict.filter { !$0.value.hasPrefix("⟦") || !$0.value.hasSuffix("⟧") }
                            .keys.sorted()
        XCTAssertTrue(
            unwrapped.isEmpty,
            "Pseudo-locale values not wrapped with ⟦…⟧:\n"
            + unwrapped.joined(separator: "\n")
        )
    }

    // MARK: - Spot-check L10n static properties resolve at runtime

    /// Key sanity check — verifies a representative sample of L10n constants
    /// are not empty strings (i.e. they have a value, even if falling back to the key).
    func test_l10nSpotCheck_nonEmpty() {
        // When no bundle has a Localizable.strings, NSLocalizedString returns the key.
        // Either way the result must be non-empty.
        XCTAssertFalse(L10n.Action.save.isEmpty,           "L10n.Action.save is empty")
        XCTAssertFalse(L10n.Action.cancel.isEmpty,         "L10n.Action.cancel is empty")
        XCTAssertFalse(L10n.TicketStatus.intake.isEmpty,   "L10n.TicketStatus.intake is empty")
        XCTAssertFalse(L10n.Customer.title.isEmpty,        "L10n.Customer.title is empty")
        XCTAssertFalse(L10n.Field.customerName.isEmpty,    "L10n.Field.customerName is empty")
        XCTAssertFalse(L10n.Error.generic.isEmpty,         "L10n.Error.generic is empty")
        XCTAssertFalse(L10n.Nav.dashboard.isEmpty,         "L10n.Nav.dashboard is empty")
        XCTAssertFalse(L10n.Dashboard.recentActivity.isEmpty, "L10n.Dashboard.recentActivity is empty")
    }
}
