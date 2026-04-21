import XCTest
import UserNotifications
@testable import Notifications

final class NotificationCategoriesTests: XCTestCase {

    // MARK: - registerAll

    func test_registerAll_returns8Categories() {
        let categories = NotificationCategories.registerAll()
        XCTAssertEqual(categories.count, 8,
            "Expected 8 categories, got \(categories.count). Category IDs: \(categories.map(\.identifier))")
    }

    func test_registerAll_allCategoryIDsCovered() {
        let categories = NotificationCategories.registerAll()
        let identifiers = Set(categories.map(\.identifier))
        for id in NotificationCategoryID.allCases {
            XCTAssertTrue(identifiers.contains(id.rawValue),
                "Missing category for NotificationCategoryID.\(id)")
        }
    }

    func test_registerAll_noDuplicateIdentifiers() {
        let categories = NotificationCategories.registerAll()
        let identifiers = categories.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count,
            "Duplicate category identifiers found: \(identifiers)")
    }

    func test_registerAll_isIdempotent() {
        let first  = NotificationCategories.registerAll().map(\.identifier).sorted()
        let second = NotificationCategories.registerAll().map(\.identifier).sorted()
        XCTAssertEqual(first, second)
    }

    // MARK: - Category ID raw values

    func test_categoryIDs_rawValues() {
        XCTAssertEqual(NotificationCategoryID.ticketUpdate.rawValue,       "bizarre.ticket.update")
        XCTAssertEqual(NotificationCategoryID.smsReply.rawValue,           "bizarre.sms.reply")
        XCTAssertEqual(NotificationCategoryID.lowStock.rawValue,           "bizarre.lowstock")
        XCTAssertEqual(NotificationCategoryID.appointmentReminder.rawValue,"bizarre.appointment.reminder")
        XCTAssertEqual(NotificationCategoryID.paymentReceived.rawValue,    "bizarre.payment.received")
        XCTAssertEqual(NotificationCategoryID.deadLetterAlert.rawValue,    "bizarre.deadletter")
        XCTAssertEqual(NotificationCategoryID.mention.rawValue,            "bizarre.mention")
        XCTAssertEqual(NotificationCategoryID.scheduleChange.rawValue,     "bizarre.schedule.change")
    }

    func test_allCases_count8() {
        XCTAssertEqual(NotificationCategoryID.allCases.count, 8)
    }

    // MARK: - Actions per category

    func test_ticketUpdate_has3Actions() {
        let cat = category(for: .ticketUpdate)
        XCTAssertEqual(cat?.actions.count, 3)
    }

    func test_ticketUpdate_actionsIdentifiers() {
        let ids = actionIDs(for: .ticketUpdate)
        XCTAssertTrue(ids.contains(NotificationActionID.ticketReply))
        XCTAssertTrue(ids.contains(NotificationActionID.ticketView))
        XCTAssertTrue(ids.contains(NotificationActionID.ticketSnooze1h))
    }

    func test_ticketUpdate_replyIsTextInput() {
        let cat = category(for: .ticketUpdate)
        let replyAction = cat?.actions.first { $0.identifier == NotificationActionID.ticketReply }
        XCTAssertTrue(replyAction is UNTextInputNotificationAction,
            "ticketReply should be a UNTextInputNotificationAction")
    }

    func test_smsReply_has2Actions() {
        let cat = category(for: .smsReply)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    func test_smsReply_quickReplyIsTextInput() {
        let cat = category(for: .smsReply)
        let action = cat?.actions.first { $0.identifier == NotificationActionID.smsQuickReply }
        XCTAssertTrue(action is UNTextInputNotificationAction)
    }

    func test_lowStock_has2Actions() {
        let cat = category(for: .lowStock)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    func test_appointmentReminder_has3Actions() {
        let cat = category(for: .appointmentReminder)
        XCTAssertEqual(cat?.actions.count, 3)
    }

    func test_paymentReceived_has2Actions() {
        let cat = category(for: .paymentReceived)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    func test_deadLetterAlert_has2Actions() {
        let cat = category(for: .deadLetterAlert)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    func test_mention_has2Actions() {
        let cat = category(for: .mention)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    func test_mention_replyIsTextInput() {
        let cat = category(for: .mention)
        let action = cat?.actions.first { $0.identifier == NotificationActionID.mentionReply }
        XCTAssertTrue(action is UNTextInputNotificationAction)
    }

    func test_scheduleChange_has2Actions() {
        let cat = category(for: .scheduleChange)
        XCTAssertEqual(cat?.actions.count, 2)
    }

    // MARK: - Helpers

    private func category(for id: NotificationCategoryID) -> UNNotificationCategory? {
        NotificationCategories.registerAll().first { $0.identifier == id.rawValue }
    }

    private func actionIDs(for id: NotificationCategoryID) -> [String] {
        category(for: id)?.actions.map(\.identifier) ?? []
    }
}
