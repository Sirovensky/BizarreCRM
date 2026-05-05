import XCTest
import UserNotifications
@testable import Notifications

@available(iOS 15.0, *)
final class NotificationInterruptionLevelTests: XCTestCase {

    func test_criticalEvents_map_toTimeSensitive() {
        let criticalEvents: [NotificationEvent] = [
            .paymentDeclined, .outOfStock, .backupFailed, .securityEvent,
            .invoiceOverdue, .cashRegisterShort, .integrationDisconnected,
        ]
        for event in criticalEvents {
            let level = NotificationInterruptionLevelMapper.level(for: event)
            XCTAssertEqual(level, .timeSensitive,
                           "Expected .timeSensitive for \(event.rawValue)")
        }
    }

    func test_normalEvents_map_toActive() {
        let normalEvents: [NotificationEvent] = [
            .ticketAssigned, .smsInbound, .invoicePaid,
            .appointmentReminder1h, .mentionInNote, .goalAchieved,
        ]
        for event in normalEvents {
            let level = NotificationInterruptionLevelMapper.level(for: event)
            XCTAssertEqual(level, .active,
                           "Expected .active for \(event.rawValue)")
        }
    }

    func test_unknownString_maps_toActive() {
        let level = NotificationInterruptionLevelMapper.level(for: "unknown.event")
        XCTAssertEqual(level, .active)
    }

    func test_quietHoursGate_suppressesWhenActive() {
        let defaults = UserDefaults(suiteName: "test.quietHoursGate.\(UUID())")!
        defaults.set(true, forKey: "notifPrefs.quietHours.enabled")
        defaults.set(0, forKey: "notifPrefs.quietHours.startHour")
        defaults.set(0, forKey: "notifPrefs.quietHours.startMinute")
        defaults.set(23, forKey: "notifPrefs.quietHours.endHour")
        defaults.set(59, forKey: "notifPrefs.quietHours.endMinute")
        // All times should be inside 00:00–23:59
        XCTAssertTrue(QuietHoursGate.isQuiet(at: Date(), defaults: defaults))
    }

    func test_quietHoursGate_notSuppressed_whenDisabled() {
        let defaults = UserDefaults(suiteName: "test.quietHoursGate.\(UUID())")!
        defaults.set(false, forKey: "notifPrefs.quietHours.enabled")
        XCTAssertFalse(QuietHoursGate.isQuiet(at: Date(), defaults: defaults))
    }

    func test_quietHoursGate_timeSensitive_notSuppressed() {
        let defaults = UserDefaults(suiteName: "test.quietHoursGate.\(UUID())")!
        defaults.set(true, forKey: "notifPrefs.quietHours.enabled")
        defaults.set(0, forKey: "notifPrefs.quietHours.startHour")
        defaults.set(0, forKey: "notifPrefs.quietHours.startMinute")
        defaults.set(23, forKey: "notifPrefs.quietHours.endHour")
        defaults.set(59, forKey: "notifPrefs.quietHours.endMinute")
        // timeSensitive events should bypass quiet hours
        XCTAssertFalse(
            QuietHoursGate.shouldSuppress(eventType: NotificationEvent.paymentDeclined.rawValue, defaults: defaults),
            "timeSensitive events must bypass quiet hours"
        )
    }

    func test_quietHoursGate_normalEvent_suppressed_duringQuietHours() {
        let defaults = UserDefaults(suiteName: "test.quietHoursGate.\(UUID())")!
        defaults.set(true, forKey: "notifPrefs.quietHours.enabled")
        defaults.set(0, forKey: "notifPrefs.quietHours.startHour")
        defaults.set(0, forKey: "notifPrefs.quietHours.startMinute")
        defaults.set(23, forKey: "notifPrefs.quietHours.endHour")
        defaults.set(59, forKey: "notifPrefs.quietHours.endMinute")
        XCTAssertTrue(
            QuietHoursGate.shouldSuppress(eventType: NotificationEvent.ticketAssigned.rawValue, defaults: defaults),
            "Normal events should be suppressed during quiet hours"
        )
    }
}
