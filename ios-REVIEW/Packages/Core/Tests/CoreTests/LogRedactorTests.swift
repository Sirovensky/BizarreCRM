import XCTest
@testable import Core

final class LogRedactorTests: XCTestCase {

    // MARK: — Email

    func test_redact_email_basic() {
        let result = LogRedactor.redact("User john.doe@example.com logged in")
        XCTAssertFalse(result.contains("@"), "email should be redacted")
        XCTAssertTrue(result.contains("<email>"))
    }

    func test_redact_email_subdomains() {
        let result = LogRedactor.redact("admin@mail.corp.example.org")
        XCTAssertTrue(result.contains("<email>"))
    }

    func test_redact_email_plusAddressing() {
        let result = LogRedactor.redact("user+tag@example.com")
        XCTAssertTrue(result.contains("<email>"))
    }

    func test_redact_email_uppercase() {
        let result = LogRedactor.redact("HELLO@EXAMPLE.COM")
        XCTAssertTrue(result.contains("<email>"))
    }

    func test_redact_email_multipleInString() {
        let result = LogRedactor.redact("From a@b.com to c@d.org")
        XCTAssertFalse(result.contains("@"))
        XCTAssertEqual(result.components(separatedBy: "<email>").count - 1, 2)
    }

    // MARK: — Phone

    func test_redact_phone_tenDigit() {
        let result = LogRedactor.redact("Called 5551234567 from server")
        XCTAssertFalse(result.contains("5551234567"))
        XCTAssertTrue(result.contains("<phone>"))
    }

    func test_redact_phone_formatted() {
        let result = LogRedactor.redact("Phone: (555) 123-4567")
        XCTAssertFalse(result.contains("555") && result.contains("4567"), "phone should be redacted")
        XCTAssertTrue(result.contains("<phone>"))
    }

    func test_redact_phone_withCountryCode() {
        let result = LogRedactor.redact("+1 (555) 123-4567")
        XCTAssertTrue(result.contains("<phone>"))
    }

    func test_redact_phone_dotSeparated() {
        let result = LogRedactor.redact("555.123.4567")
        XCTAssertTrue(result.contains("<phone>"))
    }

    // MARK: — Card PAN

    func test_redact_pan_16digits() {
        let result = LogRedactor.redact("Card 4111111111111111 declined")
        XCTAssertFalse(result.contains("4111111111111111"))
        XCTAssertTrue(result.contains("<pan>"))
    }

    func test_redact_pan_spaceSeparated() {
        let result = LogRedactor.redact("4111 1111 1111 1111")
        XCTAssertTrue(result.contains("<pan>"))
    }

    func test_redact_pan_dashSeparated() {
        let result = LogRedactor.redact("4111-1111-1111-1111")
        XCTAssertTrue(result.contains("<pan>"))
    }

    // MARK: — SSN

    func test_redact_ssn_withDashes() {
        let result = LogRedactor.redact("SSN 123-45-6789 verified")
        XCTAssertFalse(result.contains("123-45-6789"))
        XCTAssertTrue(result.contains("<ssn>"))
    }

    func test_redact_ssn_noDashes() {
        let result = LogRedactor.redact("SSN:123456789")
        XCTAssertTrue(result.contains("<ssn>"))
    }

    // MARK: — Passthrough / edge cases

    func test_redact_noSensitiveData_unchanged() {
        let input = "Ticket #1234 assigned to employee #42"
        let result = LogRedactor.redact(input)
        XCTAssertEqual(result, input, "non-PII strings should pass through unchanged")
    }

    func test_redact_empty_string() {
        XCTAssertEqual(LogRedactor.redact(""), "")
    }

    func test_redact_alreadyRedacted_passthrough() {
        // A string that already contains a placeholder should not be double-processed
        let input = "email: <email> phone: <phone>"
        let result = LogRedactor.redact(input)
        XCTAssertEqual(result, input)
    }

    func test_redact_mixedContent() {
        let input = "User john@acme.com (555-123-4567) paid with 4111111111111111"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("<email>"))
        XCTAssertTrue(result.contains("<phone>"))
        XCTAssertTrue(result.contains("<pan>"))
        XCTAssertFalse(result.contains("john"))
        XCTAssertFalse(result.contains("4111"))
    }

    func test_redact_bearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig"
        let result = LogRedactor.redact(input)
        XCTAssertTrue(result.contains("Bearer <token>"))
    }
}
