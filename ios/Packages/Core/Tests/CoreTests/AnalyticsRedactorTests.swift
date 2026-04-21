import XCTest
@testable import Core

final class AnalyticsRedactorTests: XCTestCase {

    // MARK: — PII key rejection

    func test_piiKeys_areDroppedFromProperties() {
        let piKeys = ["email", "phone", "address", "firstName", "lastName", "ssn", "creditCard"]
        for key in piKeys {
            let props: [String: AnalyticsValue] = [key: .string("sensitive value")]
            let scrubbed = AnalyticsRedactor.scrub(props)
            XCTAssertNil(scrubbed[key], "Key '\(key)' should be removed by scrubber")
        }
    }

    func test_piiKeys_caseInsensitive_areDropped() {
        let props: [String: AnalyticsValue] = [
            "Email": .string("user@example.com"),
            "PHONE": .string("555-1234"),
            "CreditCard": .string("4111111111111111")
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertTrue(scrubbed.isEmpty, "All PII-keyed entries should be dropped")
    }

    func test_nonPiiKeys_arePreserved() {
        let props: [String: AnalyticsValue] = [
            "screen": .string("dashboard"),
            "duration_ms": .int(1234),
            "retried": .bool(false)
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed.count, 3, "Non-PII keys should all be preserved")
    }

    // MARK: — String value redaction

    func test_stringValues_arePassedThroughLogRedactor() {
        let props: [String: AnalyticsValue] = [
            "description": .string("User john@example.com did something")
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        if case let .string(val) = scrubbed["description"] {
            XCTAssertFalse(val.contains("@"), "Email in string value should be redacted")
            XCTAssertTrue(val.contains("<email>"))
        } else {
            XCTFail("description key should be present with string value")
        }
    }

    func test_phoneInStringValue_isRedacted() {
        let props: [String: AnalyticsValue] = [
            "note": .string("Call back at 555-123-4567")
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        if case let .string(val) = scrubbed["note"] {
            XCTAssertTrue(val.contains("<phone>"), "Phone in string value should be redacted")
        } else {
            XCTFail("note key should be present")
        }
    }

    // MARK: — Non-string values unchanged

    func test_intValues_areNotAltered() {
        let props: [String: AnalyticsValue] = ["count": .int(42)]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed["count"], .int(42))
    }

    func test_doubleValues_areNotAltered() {
        let props: [String: AnalyticsValue] = ["latency": .double(1.23)]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed["latency"], .double(1.23))
    }

    func test_boolValues_areNotAltered() {
        let props: [String: AnalyticsValue] = ["success": .bool(true)]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed["success"], .bool(true))
    }

    func test_nullValues_areNotAltered() {
        let props: [String: AnalyticsValue] = ["optional_field": .null]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertEqual(scrubbed["optional_field"], .null)
    }

    // MARK: — Mixed PII and non-PII

    func test_mixedDict_onlyDropsPiiKeys_andRedactsStrings() {
        let props: [String: AnalyticsValue] = [
            "email": .string("user@example.com"),     // dropped (PII key)
            "screen": .string("tickets"),              // kept
            "priority": .string("high"),               // kept
            "ssn": .string("123-45-6789")             // dropped (PII key)
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        XCTAssertNil(scrubbed["email"])
        XCTAssertNil(scrubbed["ssn"])
        XCTAssertNotNil(scrubbed["screen"])
        XCTAssertNotNil(scrubbed["priority"])
    }

    // MARK: — Empty dict

    func test_emptyDict_returnsEmpty() {
        let scrubbed = AnalyticsRedactor.scrub([:])
        XCTAssertTrue(scrubbed.isEmpty)
    }

    // MARK: — Partial PII substring in key does NOT drop it

    func test_partialPiiSubstring_inKey_isNotDropped() {
        // "emailNotifications" is not a PII field — should NOT be dropped
        let props: [String: AnalyticsValue] = [
            "emailNotificationsEnabled": .bool(true)
        ]
        let scrubbed = AnalyticsRedactor.scrub(props)
        // This key contains "email" but is not an exact PII key match
        // Implementation decides exact vs substring match; test documents behavior
        // Based on spec: reject keys that "look like PII" — we test exact match here
        XCTAssertNotNil(scrubbed["emailNotificationsEnabled"],
            "Partial substring 'email' in a different key should not be stripped")
    }
}
