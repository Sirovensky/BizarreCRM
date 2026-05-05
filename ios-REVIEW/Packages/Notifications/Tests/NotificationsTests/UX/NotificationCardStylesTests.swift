import Testing
import Foundation
@testable import Notifications
@testable import Networking

// MARK: - NotificationCardStylesTests

@Suite("NotificationCardStyles")
struct NotificationCardStylesTests {

    // MARK: - NotificationCardStyle equality

    @Test("compact equals compact")
    func compactEquality() {
        #expect(NotificationCardStyle.compact == NotificationCardStyle.compact)
    }

    @Test("expanded equals expanded")
    func expandedEquality() {
        #expect(NotificationCardStyle.expanded == NotificationCardStyle.expanded)
    }

    @Test("grouped equals grouped with same count")
    func groupedEqualitySameCount() {
        #expect(NotificationCardStyle.grouped(count: 3) == NotificationCardStyle.grouped(count: 3))
    }

    @Test("grouped not equal when count differs")
    func groupedInequalityDifferentCount() {
        #expect(NotificationCardStyle.grouped(count: 2) != NotificationCardStyle.grouped(count: 5))
    }

    @Test("compact not equal to expanded")
    func compactNotEqualToExpanded() {
        #expect(NotificationCardStyle.compact != NotificationCardStyle.expanded)
    }

    @Test("expanded not equal to grouped")
    func expandedNotEqualToGrouped() {
        #expect(NotificationCardStyle.expanded != NotificationCardStyle.grouped(count: 1))
    }

    // MARK: - NotificationItem.read

    @Test("item read = false when isRead = 0")
    func itemReadFalse() {
        let item = makeItem(id: 1, isRead: 0)
        #expect(!item.read)
    }

    @Test("item read = true when isRead = 1")
    func itemReadTrue() {
        let item = makeItem(id: 1, isRead: 1)
        #expect(item.read)
    }

    @Test("item read = false when isRead = nil")
    func itemReadNil() {
        let item = makeItem(id: 1, isRead: nil)
        #expect(!item.read)
    }

    // MARK: - NotificationItem fields

    @Test("item id is preserved")
    func itemIdPreserved() {
        let item = makeItem(id: 42)
        #expect(item.id == 42)
    }

    @Test("item type is preserved")
    func itemTypePreserved() {
        let item = makeItem(id: 1, type: "ticket.assigned")
        #expect(item.type == "ticket.assigned")
    }

    @Test("item title is preserved")
    func itemTitlePreserved() {
        let item = makeItem(id: 1, title: "New ticket")
        #expect(item.title == "New ticket")
    }

    @Test("item message is preserved")
    func itemMessagePreserved() {
        let item = makeItem(id: 1, message: "You have a new ticket")
        #expect(item.message == "You have a new ticket")
    }

    @Test("item entityType is preserved")
    func itemEntityTypePreserved() {
        let item = makeItem(id: 1, entityType: "ticket")
        #expect(item.entityType == "ticket")
    }

    @Test("item entityId is preserved")
    func itemEntityIdPreserved() {
        let item = makeItem(id: 1, entityId: 99)
        #expect(item.entityId == 99)
    }

    // MARK: - Helpers

    private func makeItem(
        id: Int64,
        type: String? = "ticket",
        title: String? = "Test notification",
        message: String? = "Test body",
        entityType: String? = nil,
        entityId: Int64? = nil,
        isRead: Int? = 0,
        createdAt: String? = "2026-04-23T10:00:00Z"
    ) -> NotificationItem {
        .init(
            id: id,
            type: type,
            title: title,
            message: message,
            entityType: entityType,
            entityId: entityId,
            isRead: isRead,
            createdAt: createdAt
        )
    }
}
