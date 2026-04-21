import XCTest
@testable import Notifications

final class NotificationPriorityTests: XCTestCase {

    // MARK: - Comparable

    func test_priority_comparable_criticalHighest() {
        XCTAssertGreaterThan(NotificationPriority.critical, .timeSensitive)
        XCTAssertGreaterThan(NotificationPriority.timeSensitive, .normal)
        XCTAssertGreaterThan(NotificationPriority.normal, .low)
    }

    // MARK: - APNs priority header

    func test_apnsPriorityHeader_lowAndNormal_return5() {
        XCTAssertEqual(NotificationPriority.low.apnsPriorityHeader, 5)
        XCTAssertEqual(NotificationPriority.normal.apnsPriorityHeader, 5)
    }

    func test_apnsPriorityHeader_timeSensitiveAndCritical_return10() {
        XCTAssertEqual(NotificationPriority.timeSensitive.apnsPriorityHeader, 10)
        XCTAssertEqual(NotificationPriority.critical.apnsPriorityHeader, 10)
    }

    // MARK: - Event mapping

    func test_defaultPriority_backupFailed_isCritical() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .backupFailed), .critical)
    }

    func test_defaultPriority_securityEvent_isCritical() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .securityEvent), .critical)
    }

    func test_defaultPriority_paymentDeclined_isCritical() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .paymentDeclined), .critical)
    }

    func test_defaultPriority_outOfStock_isCritical() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .outOfStock), .critical)
    }

    func test_defaultPriority_ticketAssigned_isTimeSensitive() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .ticketAssigned), .timeSensitive)
    }

    func test_defaultPriority_smsInbound_isTimeSensitive() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .smsInbound), .timeSensitive)
    }

    func test_defaultPriority_invoicePaid_isNormal() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .invoicePaid), .normal)
    }

    func test_defaultPriority_campaignSent_isLow() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .campaignSent), .low)
    }

    func test_defaultPriority_setupWizardIncomplete_isLow() {
        XCTAssertEqual(NotificationPriority.defaultPriority(for: .setupWizardIncomplete), .low)
    }

    // MARK: - All events have a priority

    func test_defaultPriority_allEventsCovered() {
        for event in NotificationEvent.allCases {
            let p = NotificationPriority.defaultPriority(for: event)
            // Just verifying it doesn't crash and returns a valid value
            XCTAssertTrue(NotificationPriority.allCases.contains(p), "Event \(event.rawValue) has no valid priority")
        }
    }

    // MARK: - Display

    func test_displayName_notEmpty() {
        for p in NotificationPriority.allCases {
            XCTAssertFalse(p.displayName.isEmpty)
        }
    }

    func test_iconName_notEmpty() {
        for p in NotificationPriority.allCases {
            XCTAssertFalse(p.iconName.isEmpty)
        }
    }

    func test_accessibilityLabel_notEmpty() {
        for p in NotificationPriority.allCases {
            XCTAssertFalse(p.accessibilityLabel.isEmpty)
        }
    }

    // MARK: - Raw values

    func test_rawValues_unique() {
        let rawValues = NotificationPriority.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    func test_allCases_count4() {
        XCTAssertEqual(NotificationPriority.allCases.count, 4)
    }
}
