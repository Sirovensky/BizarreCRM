import XCTest
import UserNotifications
@testable import Notifications

final class NotificationCategoriesTests: XCTestCase {

    // MARK: - registerAll

    func test_registerAll_returns9Categories() {
        let categories = NotificationCategories.registerAll()
        XCTAssertEqual(categories.count, 9,
            "Expected 9 categories, got \(categories.count). Category IDs: \(categories.map(\.identifier))")
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
        XCTAssertEqual(NotificationCategoryID.paymentFailed.rawValue,      "bizarre.payment.failed")
        XCTAssertEqual(NotificationCategoryID.deadLetterAlert.rawValue,    "bizarre.deadletter")
        XCTAssertEqual(NotificationCategoryID.mention.rawValue,            "bizarre.mention")
        XCTAssertEqual(NotificationCategoryID.scheduleChange.rawValue,     "bizarre.schedule.change")
    }

    func test_allCases_count9() {
        XCTAssertEqual(NotificationCategoryID.allCases.count, 9)
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

    // §21.2 PAYMENT_FAILED
    func test_paymentFailed_has2Actions() {
        let cat = category(for: .paymentFailed)
        XCTAssertEqual(cat?.actions.count, 2, "PAYMENT_FAILED should have Open + Retry Charge actions")
    }

    func test_paymentFailed_actionsIdentifiers() {
        let ids = actionIDs(for: .paymentFailed)
        XCTAssertTrue(ids.contains(NotificationActionID.paymentFailedView),
            "PAYMENT_FAILED missing 'Open' action")
        XCTAssertTrue(ids.contains(NotificationActionID.paymentFailedRetry),
            "PAYMENT_FAILED missing 'Retry Charge' action")
    }

    func test_paymentFailed_retryIsDestructive() {
        let cat = category(for: .paymentFailed)
        let retry = cat?.actions.first { $0.identifier == NotificationActionID.paymentFailedRetry }
        XCTAssertNotNil(retry, "Retry action not found in PAYMENT_FAILED category")
        XCTAssertTrue(retry?.options.contains(.destructive) == true,
            "Retry Charge should be destructive (financial re-attempt)")
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
