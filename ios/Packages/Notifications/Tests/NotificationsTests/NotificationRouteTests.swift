import XCTest
@testable import Notifications

// MARK: - NotificationRouteTests
//
// Tests for NotificationRoute.from(userInfo:) — the structured deep-link resolver.
// All cases are pure (no UIKit / network needed).

final class NotificationRouteTests: XCTestCase {

    // MARK: - Pre-formed deep-link URL

    func test_fromUserInfo_preformedURL_ticket() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://ticket/42"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .ticket(id: 42))
    }

    func test_fromUserInfo_preformedURL_customer() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://customer/7"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .customer(id: 7))
    }

    func test_fromUserInfo_preformedURL_invoice() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://invoice/100"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .invoice(id: 100))
    }

    func test_fromUserInfo_preformedURL_estimate() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://estimate/55"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .estimate(id: 55))
    }

    func test_fromUserInfo_preformedURL_appointment() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://appointment/9"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .appointment(id: 9))
    }

    func test_fromUserInfo_preformedURL_sms() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://sms/3"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .smsThread(id: 3))
    }

    func test_fromUserInfo_preformedURL_thread() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://thread/8"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .thread(id: 8))
    }

    func test_fromUserInfo_preformedURL_expense() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://expense/21"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .expense(id: 21))
    }

    func test_fromUserInfo_preformedURL_lead() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://lead/15"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .lead(id: 15))
    }

    func test_fromUserInfo_preformedURL_employee() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://employee/2"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .employee(id: 2))
    }

    func test_fromUserInfo_preformedURL_notification() {
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://notification/88"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .notification(id: 88))
    }

    // MARK: - Reject non-bizarrecrm schemes

    func test_fromUserInfo_httpURLIsIgnored_fallsBackToEntityType() {
        // http URL in deepLink must not be used; falls back to entityType
        let userInfo: [AnyHashable: Any] = [
            "deepLink": "https://example.com/tickets/5",
            "entity_type": "ticket",
            "entity_id": 5
        ]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .ticket(id: 5))
    }

    // MARK: - entityType + entityId fallback

    func test_fromUserInfo_entityType_ticket_camelCase() {
        let userInfo: [AnyHashable: Any] = ["entityType": "ticket", "entityId": 10]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .ticket(id: 10))
    }

    func test_fromUserInfo_entityType_ticket_snakeCase() {
        let userInfo: [AnyHashable: Any] = ["entity_type": "TICKET", "entity_id": "99"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .ticket(id: 99))
    }

    func test_fromUserInfo_entityType_customer_stringId() {
        let userInfo: [AnyHashable: Any] = ["entity_type": "customer", "entity_id": "17"]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .customer(id: 17))
    }

    func test_fromUserInfo_entityType_invoice() {
        let userInfo: [AnyHashable: Any] = ["entityType": "invoice", "entityId": 33]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .invoice(id: 33))
    }

    func test_fromUserInfo_entityType_appointment() {
        let userInfo: [AnyHashable: Any] = ["entityType": "appointment", "entityId": 4]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .appointment(id: 4))
    }

    func test_fromUserInfo_entityType_sms() {
        let userInfo: [AnyHashable: Any] = ["entityType": "sms", "entityId": 6]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .smsThread(id: 6))
    }

    // MARK: - Unknown entity type

    func test_fromUserInfo_unknownEntityType_returnsUnknown() {
        let userInfo: [AnyHashable: Any] = ["entityType": "widgetboard", "entityId": 1]
        let route = NotificationRoute.from(userInfo: userInfo)
        if case .unknown(let type) = route {
            XCTAssertEqual(type, "widgetboard")
        } else {
            XCTFail("Expected .unknown, got \(String(describing: route))")
        }
    }

    // MARK: - Missing entity type

    func test_fromUserInfo_noEntityType_returnsNil() {
        let userInfo: [AnyHashable: Any] = ["entityId": 5]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertNil(route)
    }

    func test_fromUserInfo_emptyUserInfo_returnsNil() {
        let route = NotificationRoute.from(userInfo: [:])
        XCTAssertNil(route)
    }

    // MARK: - Missing entity ID

    func test_fromUserInfo_missingEntityId_returnsUnknown() {
        let userInfo: [AnyHashable: Any] = ["entityType": "ticket"]
        let route = NotificationRoute.from(userInfo: userInfo)
        if case .unknown(let type) = route {
            XCTAssertEqual(type, "ticket")
        } else {
            XCTFail("Expected .unknown(entityType: ticket), got \(String(describing: route))")
        }
    }

    // MARK: - ID type coercions

    func test_fromUserInfo_int64EntityId() {
        let userInfo: [AnyHashable: Any] = ["entityType": "invoice", "entityId": Int64(999)]
        let route = NotificationRoute.from(userInfo: userInfo)
        XCTAssertEqual(route, .invoice(id: 999))
    }

    func test_fromUserInfo_negativeEntityId_returnsUnknownOrNegative() {
        // Negative IDs are technically invalid server-side but the parser should not crash.
        let userInfo: [AnyHashable: Any] = ["entityType": "ticket", "entityId": -1]
        let route = NotificationRoute.from(userInfo: userInfo)
        // Either .ticket(id:-1) or .unknown is acceptable — just no crash.
        XCTAssertNotNil(route)
    }

    // MARK: - deepLink URL with no path component

    func test_fromUserInfo_preformedURL_noPathId_returnsUnknown() {
        // bizarrecrm://ticket with no path → entityId is nil
        let userInfo: [AnyHashable: Any] = ["deepLink": "bizarrecrm://ticket"]
        let route = NotificationRoute.from(userInfo: userInfo)
        if case .unknown(let type) = route {
            XCTAssertEqual(type, "ticket")
        } else {
            XCTFail("Expected .unknown for URL without ID, got \(String(describing: route))")
        }
    }
}
