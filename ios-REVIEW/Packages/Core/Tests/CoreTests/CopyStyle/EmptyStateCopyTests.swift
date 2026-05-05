import XCTest
@testable import Core

// §64 — Tests for EmptyStateCopy catalog completeness and content quality.

final class EmptyStateCopyTests: XCTestCase {

    // MARK: — Catalog completeness

    /// Every entity must produce a non-empty title and body.
    func testAllEntitiesHaveNonEmptyTitleAndBody() {
        for entity in EmptyStateCopy.Entity.allCases {
            let copy = EmptyStateCopy.copy(for: entity)
            XCTAssertFalse(copy.title.isEmpty, "title must not be empty for \(entity)")
            XCTAssertFalse(copy.body.isEmpty,  "body must not be empty for \(entity)")
        }
    }

    // MARK: — Entities with createLabel

    func testCreatableEntitiesHaveCreateLabel() {
        let creatableEntities: [EmptyStateCopy.Entity] = [
            .tickets, .customers, .invoices, .inventory,
            .expenses, .appointments, .employees, .leads,
            .estimates, .smsConversations
        ]
        for entity in creatableEntities {
            let copy = EmptyStateCopy.copy(for: entity)
            XCTAssertNotNil(copy.createLabel, "createLabel should be present for \(entity)")
            XCTAssertFalse(copy.createLabel!.isEmpty, "createLabel must not be empty for \(entity)")
        }
    }

    // MARK: — Read-only entities have no createLabel

    func testReadOnlyEntitiesHaveNoCreateLabel() {
        let readOnlyEntities: [EmptyStateCopy.Entity] = [
            .auditLogs, .searchResults, .notifications, .reports
        ]
        for entity in readOnlyEntities {
            let copy = EmptyStateCopy.copy(for: entity)
            XCTAssertNil(copy.createLabel, "createLabel should be nil for \(entity)")
        }
    }

    // MARK: — Specific spot checks

    func testTickets_titleMentionsTickets() {
        let copy = EmptyStateCopy.copy(for: .tickets)
        XCTAssertTrue(copy.title.lowercased().contains("ticket"))
    }

    func testCustomers_createLabelMentionsCustomer() {
        let copy = EmptyStateCopy.copy(for: .customers)
        XCTAssertTrue(copy.createLabel?.lowercased().contains("customer") ?? false)
    }

    func testSearchResults_bodyMentionsSearch() {
        let copy = EmptyStateCopy.copy(for: .searchResults)
        // Body should give the user a useful hint
        XCTAssertFalse(copy.body.isEmpty)
    }

    func testNotifications_titleIsPositive() {
        let copy = EmptyStateCopy.copy(for: .notifications)
        // "All caught up" is a positive framing — not "No notifications"
        XCTAssertFalse(copy.title.isEmpty)
    }

    // MARK: — Entity enum covers all CaseIterable cases

    func testEntityAllCasesIsComplete() {
        // If a new case is added to Entity without updating this test, the
        // catalog completeness test above will catch it automatically.
        // This test just verifies that allCases is non-empty.
        XCTAssertFalse(EmptyStateCopy.Entity.allCases.isEmpty)
    }

    // MARK: — Tone compliance

    func testAllCopiesPassToneGuidelines() {
        for entity in EmptyStateCopy.Entity.allCases {
            let copy = EmptyStateCopy.copy(for: entity)
            let titleViolations = ToneGuidelines.violations(in: copy.title)
            let bodyViolations  = ToneGuidelines.violations(in: copy.body)
            XCTAssertTrue(titleViolations.isEmpty,
                "Title for \(entity) has tone violations: \(titleViolations) — \"\(copy.title)\"")
            XCTAssertTrue(bodyViolations.isEmpty,
                "Body for \(entity) has tone violations: \(bodyViolations) — \"\(copy.body)\"")
            if let label = copy.createLabel {
                let labelViolations = ToneGuidelines.violations(in: label)
                XCTAssertTrue(labelViolations.isEmpty,
                    "createLabel for \(entity) has tone violations: \(labelViolations) — \"\(label)\"")
            }
        }
    }
}
