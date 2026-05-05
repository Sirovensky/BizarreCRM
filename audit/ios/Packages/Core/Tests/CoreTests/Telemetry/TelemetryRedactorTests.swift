import XCTest
@testable import Core

// §32 Telemetry Sovereignty Guardrails — TelemetryRedactor unit tests

final class TelemetryRedactorTests: XCTestCase {

    // MARK: - PII key rejection

    func test_emailKey_isDropped() {
        let result = TelemetryRedactor.scrub(["email": "user@example.com"])
        XCTAssertNil(result["email"])
    }

    func test_phoneKey_isDropped() {
        let result = TelemetryRedactor.scrub(["phone": "555-123-4567"])
        XCTAssertNil(result["phone"])
    }

    func test_customerNameKey_isDropped() {
        let result = TelemetryRedactor.scrub(["customerName": "Alice Smith"])
        XCTAssertNil(result["customerName"])
    }

    func test_customerNameSnakeCase_isDropped() {
        let result = TelemetryRedactor.scrub(["customer_name": "Bob Jones"])
        XCTAssertNil(result["customer_name"])
    }

    func test_firstNameKey_isDropped() {
        let result = TelemetryRedactor.scrub(["firstName": "Alice"])
        XCTAssertNil(result["firstName"])
    }

    func test_lastNameKey_isDropped() {
        let result = TelemetryRedactor.scrub(["lastName": "Smith"])
        XCTAssertNil(result["lastName"])
    }

    func test_ssnKey_isDropped() {
        let result = TelemetryRedactor.scrub(["ssn": "123-45-6789"])
        XCTAssertNil(result["ssn"])
    }

    func test_creditCardKey_isDropped() {
        let result = TelemetryRedactor.scrub(["creditCard": "4111111111111111"])
        XCTAssertNil(result["creditCard"])
    }

    func test_piiKeys_caseInsensitive_areDropped() {
        let props = [
            "EMAIL": "user@example.com",
            "Phone": "555-000-1111",
            "CREDITCARD": "4111111111111111",
        ]
        let result = TelemetryRedactor.scrub(props)
        XCTAssertTrue(result.isEmpty, "All PII-keyed entries should be dropped case-insensitively")
    }

    // MARK: - Non-PII keys preserved

    func test_nonPiiKeys_arePreserved() {
        let props = [
            "screen": "dashboard",
            "build": "42",
            "locale": "en-US",
        ]
        let result = TelemetryRedactor.scrub(props)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result["screen"], "dashboard")
        XCTAssertEqual(result["build"], "42")
        XCTAssertEqual(result["locale"], "en-US")
    }

    func test_partialPiiSubstring_inKey_isNotDropped() {
        // "emailNotifications" is NOT an exact PII field — must not be stripped.
        let result = TelemetryRedactor.scrub(["emailNotificationsEnabled": "true"])
        XCTAssertNotNil(result["emailNotificationsEnabled"],
                        "'email' substring in a different key must not cause key rejection")
    }

    // MARK: - Email redaction in values

    func test_emailInValue_isRedacted() {
        let result = TelemetryRedactor.scrub(["note": "Sent to user@example.com today"])
        XCTAssertEqual(result["note"], "Sent to <email> today")
    }

    func test_multipleEmailsInValue_areAllRedacted() {
        let result = TelemetryRedactor.scrub(["body": "From alice@x.com to bob@y.org"])
        let value = result["body"] ?? ""
        XCTAssertFalse(value.contains("@"), "No email addresses should survive redaction")
        XCTAssertEqual(value.components(separatedBy: "<email>").count - 1, 2,
                       "Both email addresses should be replaced")
    }

    // MARK: - Phone redaction in values

    func test_phoneInValue_isRedacted() {
        let result = TelemetryRedactor.scrub(["note": "Call 555-123-4567 asap"])
        let value = result["note"] ?? ""
        XCTAssertTrue(value.contains("<phone>"), "Phone number should be replaced with <phone>")
        XCTAssertFalse(value.contains("555-123-4567"))
    }

    func test_internationalPhoneInValue_isRedacted() {
        let result = TelemetryRedactor.scrub(["contact": "+1 (800) 555-1234"])
        let value = result["contact"] ?? ""
        XCTAssertTrue(value.contains("<phone>"))
    }

    // MARK: - Empty & edge cases

    func test_emptyDict_returnsEmpty() {
        XCTAssertTrue(TelemetryRedactor.scrub([:]).isEmpty)
    }

    func test_valueWithNoPatterns_isUnchanged() {
        let result = TelemetryRedactor.scrub(["status": "active"])
        XCTAssertEqual(result["status"], "active")
    }

    func test_mixedDict_dropsPiiKeys_andRedactsValues() {
        let props = [
            "email": "drop@me.com",          // dropped (PII key)
            "screen": "tickets",              // kept as-is
            "note": "cb 555-999-8888",        // kept, phone redacted
        ]
        let result = TelemetryRedactor.scrub(props)
        XCTAssertNil(result["email"], "PII key must be dropped")
        XCTAssertEqual(result["screen"], "tickets")
        let note = result["note"] ?? ""
        XCTAssertTrue(note.contains("<phone>"))
        XCTAssertFalse(note.contains("555-999-8888"))
    }
}
