// §22 TechRosterEntryTests — tests for TechRosterEntry model and TechStatus.

import XCTest
@testable import FieldService
import Networking

final class TechRosterEntryTests: XCTestCase {

    // MARK: - TechStatus displayLabel

    func test_techStatus_displayLabels_areNonEmpty() {
        for status in [TechStatus.available, .busy, .enRoute, .offline] {
            XCTAssertFalse(status.displayLabel.isEmpty, "\(status) has empty displayLabel")
        }
    }

    func test_techStatus_available_displayLabel() {
        XCTAssertEqual(TechStatus.available.displayLabel, "Available")
    }

    func test_techStatus_enRoute_displayLabel() {
        XCTAssertEqual(TechStatus.enRoute.displayLabel, "En Route")
    }

    func test_techStatus_busy_displayLabel() {
        XCTAssertEqual(TechStatus.busy.displayLabel, "Busy")
    }

    func test_techStatus_offline_displayLabel() {
        XCTAssertEqual(TechStatus.offline.displayLabel, "Offline")
    }

    // MARK: - TechRosterEntry identity

    func test_rosterEntry_id_matchesTechId() {
        let emp = Employee.makeTestiPad(id: 77, firstName: "Dana", lastName: "C")
        let entry = TechRosterEntry(tech: emp, currentStatus: .available, assignedJobCount: 2)

        XCTAssertEqual(entry.id, 77)
    }

    func test_rosterEntry_equalityViaTechId() {
        let emp1 = Employee.makeTestiPad(id: 1, firstName: "Alice", lastName: "A")
        let emp2 = Employee.makeTestiPad(id: 1, firstName: "Alice", lastName: "A")
        let e1 = TechRosterEntry(tech: emp1, currentStatus: .available, assignedJobCount: 0)
        let e2 = TechRosterEntry(tech: emp2, currentStatus: .available, assignedJobCount: 0)

        XCTAssertEqual(e1, e2)
    }

    func test_rosterEntry_notEqualWhenStatusDiffers() {
        let emp = Employee.makeTestiPad(id: 1, firstName: "X", lastName: "Y")
        let e1 = TechRosterEntry(tech: emp, currentStatus: .available, assignedJobCount: 0)
        let e2 = TechRosterEntry(tech: emp, currentStatus: .busy,      assignedJobCount: 0)

        XCTAssertNotEqual(e1, e2)
    }

    // MARK: - DispatcherShortcutsCatalog

    func test_shortcutsCatalog_hasExpectedEntries() {
        let catalog = DispatcherShortcutsCatalog.entries
        XCTAssertEqual(catalog.count, 4)
    }

    func test_shortcutsCatalog_cmdN_assignNextUnassigned() {
        let entries = DispatcherShortcutsCatalog.entries
        let entry = entries.first { $0.symbol == "N" && $0.modifiers.contains("⌘") }
        XCTAssertNotNil(entry, "⌘N entry not found in catalog")
    }

    func test_shortcutsCatalog_cmdF_findJobs() {
        let entries = DispatcherShortcutsCatalog.entries
        let entry = entries.first { $0.symbol == "F" && $0.modifiers.contains("⌘") }
        XCTAssertNotNil(entry, "⌘F entry not found in catalog")
    }

    func test_shortcutsCatalog_j_selectNext() {
        let entries = DispatcherShortcutsCatalog.entries
        let entry = entries.first { $0.symbol == "J" && $0.modifiers.isEmpty }
        XCTAssertNotNil(entry, "J entry not found in catalog")
    }

    func test_shortcutsCatalog_k_selectPrev() {
        let entries = DispatcherShortcutsCatalog.entries
        let entry = entries.first { $0.symbol == "K" && $0.modifiers.isEmpty }
        XCTAssertNotNil(entry, "K entry not found in catalog")
    }

    func test_shortcutsCatalog_allEntriesHaveDescriptions() {
        for entry in DispatcherShortcutsCatalog.entries {
            XCTAssertFalse(entry.description.isEmpty, "Catalog entry \(entry.symbol) has empty description")
        }
    }
}
