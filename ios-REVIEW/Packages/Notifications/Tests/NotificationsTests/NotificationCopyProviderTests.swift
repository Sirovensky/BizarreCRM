import XCTest
@testable import Notifications

// MARK: - §70 NotificationCopyProvider tests

final class NotificationCopyProviderTests: XCTestCase {

    // MARK: - SMS inbound

    func test_smsInbound_withCustomerName_includesName() {
        let copy = NotificationCopyProvider.copy(
            for: .smsInbound,
            context: ["customerName": "John Smith", "messagePreview": "Hi there!"]
        )
        XCTAssertEqual(copy.title, "SMS from John Smith")
        XCTAssertEqual(copy.body, "Hi there!")
        XCTAssertEqual(copy.categoryID, NotificationCategoryID.smsReply.rawValue)
    }

    func test_smsInbound_noContext_hasDefaultTitle() {
        let copy = NotificationCopyProvider.copy(for: .smsInbound)
        XCTAssertEqual(copy.title, "New SMS")
        XCTAssertFalse(copy.body.isEmpty)
    }

    // MARK: - Invoice paid

    func test_invoicePaid_withAmountAndCustomer_includesBoth() {
        let copy = NotificationCopyProvider.copy(
            for: .invoicePaid,
            context: ["invoiceId": "1001", "amount": "125.00", "customerName": "Jane Doe"]
        )
        XCTAssertEqual(copy.title, "Payment received")
        XCTAssertTrue(copy.body.contains("1001"))
        XCTAssertTrue(copy.body.contains("$125.00"))
        XCTAssertTrue(copy.body.contains("Jane Doe"))
    }

    // MARK: - Ticket assigned

    func test_ticketAssigned_withIdAndDevice_includesBoth() {
        let copy = NotificationCopyProvider.copy(
            for: .ticketAssigned,
            context: ["ticketId": "T-42", "device": "iPhone 15 Pro"]
        )
        XCTAssertEqual(copy.title, "Ticket assigned to you")
        XCTAssertTrue(copy.body.contains("T-42"))
        XCTAssertTrue(copy.body.contains("iPhone 15 Pro"))
        XCTAssertEqual(copy.categoryID, NotificationCategoryID.ticketUpdate.rawValue)
    }

    // MARK: - Critical events

    func test_backupFailed_hasCriticalTone() {
        let copy = NotificationCopyProvider.copy(for: .backupFailed)
        XCTAssertEqual(copy.title, "Backup failed")
        XCTAssertFalse(copy.body.isEmpty)
        XCTAssertNil(copy.categoryID)
    }

    func test_securityEvent_hasUrgentBody() {
        let copy = NotificationCopyProvider.copy(for: .securityEvent)
        XCTAssertEqual(copy.title, "Security alert")
        XCTAssertTrue(copy.body.contains("immediately"))
    }

    // MARK: - Low stock

    func test_lowStock_withSKUAndCount_includesBoth() {
        let copy = NotificationCopyProvider.copy(
            for: .lowStock,
            context: ["sku": "SKU-001", "count": "3"]
        )
        XCTAssertTrue(copy.body.contains("SKU-001"))
        XCTAssertTrue(copy.body.contains("3"))
    }

    // MARK: - All events produce non-empty copy

    func test_allEvents_haveNonEmptyTitleAndBody() {
        for event in NotificationEvent.allCases {
            let copy = NotificationCopyProvider.copy(for: event)
            XCTAssertFalse(copy.title.isEmpty, "Title empty for event: \(event.rawValue)")
            XCTAssertFalse(copy.body.isEmpty, "Body empty for event: \(event.rawValue)")
        }
    }

    // MARK: - No emoji in titles (§70 tone rule)

    func test_allEvents_titlesContainNoEmoji() {
        for event in NotificationEvent.allCases {
            let copy = NotificationCopyProvider.copy(for: event)
            XCTAssertFalse(copy.title.unicodeScalars.contains(where: { $0.properties.isEmoji && $0.value > 0xFF }),
                           "Emoji found in title for event: \(event.rawValue)")
        }
    }
}
