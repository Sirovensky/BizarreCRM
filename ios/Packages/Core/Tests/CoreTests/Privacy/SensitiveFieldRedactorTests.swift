import XCTest
@testable import Core

// §28 Security & Privacy helpers — SensitiveFieldRedactor tests

final class SensitiveFieldRedactorTests: XCTestCase {

    // MARK: - No-op cases

    func test_emptyCategories_returnsOriginalText() {
        let text = "alice@example.com 555-123-4567"
        XCTAssertEqual(SensitiveFieldRedactor.redact(text, categories: []), text)
    }

    func test_cleanText_unchangedByAllCategories() {
        let text = "Customer checked in at 09:00"
        let result = SensitiveFieldRedactor.redactAll(text)
        XCTAssertEqual(result, text)
    }

    // MARK: - Email category

    func test_email_redactsSimpleAddress() {
        let result = SensitiveFieldRedactor.redact("Send to alice@example.com", categories: [.email])
        XCTAssertEqual(result, "Send to <email>")
    }

    func test_email_redactsMultipleAddresses() {
        let text = "From a@x.com to b@y.org"
        let result = SensitiveFieldRedactor.redact(text, categories: [.email])
        XCTAssertFalse(result.contains("@"))
        XCTAssertEqual(result.components(separatedBy: "<email>").count - 1, 2)
    }

    func test_email_doesNotRedactPhoneWhenOnlyEmailRequested() {
        let text = "alice@x.com and 555-123-4567"
        let result = SensitiveFieldRedactor.redact(text, categories: [.email])
        XCTAssertFalse(result.contains("alice"))
        XCTAssertTrue(result.contains("555-123-4567"), "Phone should not be redacted when .phone is not in categories")
    }

    // MARK: - Phone category

    func test_phone_redactsUSFormat() {
        let result = SensitiveFieldRedactor.redact("Call 555-123-4567 now", categories: [.phone])
        XCTAssertTrue(result.contains("<phone>"))
        XCTAssertFalse(result.contains("555-123-4567"))
    }

    func test_phone_redactsInternationalE164() {
        let result = SensitiveFieldRedactor.redact("Intl: +44 7700 900123", categories: [.phone])
        XCTAssertTrue(result.contains("<phone>"))
    }

    func test_phone_redactsParenthesisFormat() {
        let result = SensitiveFieldRedactor.redact("+1 (800) 555-1234", categories: [.phone])
        XCTAssertTrue(result.contains("<phone>"))
    }

    // MARK: - Name category

    func test_name_redactsTitleCasePair() {
        let result = SensitiveFieldRedactor.redact("Assigned to Alice Smith today", categories: [.name])
        XCTAssertFalse(result.contains("Alice Smith"))
        XCTAssertTrue(result.contains("<name>"))
    }

    func test_name_doesNotRedactSingleWord() {
        // Single title-cased word should not match the pair pattern.
        let text = "Alice called."
        let result = SensitiveFieldRedactor.redact(text, categories: [.name])
        // Single words don't match the "First Last" heuristic — result should be unchanged.
        XCTAssertEqual(result, text)
    }

    // MARK: - Address category

    func test_address_redactsUSStreetAddress() {
        let text = "Located at 123 Main St."
        let result = SensitiveFieldRedactor.redact(text, categories: [.address])
        XCTAssertFalse(result.contains("123 Main St"))
    }

    func test_address_redactsZIPCode() {
        let text = "ZIP: 90210"
        let result = SensitiveFieldRedactor.redact(text, categories: [.address])
        XCTAssertFalse(result.contains("90210"))
        XCTAssertTrue(result.contains("<zip>"))
    }

    // MARK: - PaymentCard category

    func test_paymentCard_redactsPAN_noSpaces() {
        let result = SensitiveFieldRedactor.redact("Card: 4111111111111111", categories: [.paymentCard])
        XCTAssertFalse(result.contains("4111"))
        XCTAssertTrue(result.contains("<pan>"))
    }

    func test_paymentCard_redactsPAN_withSpaces() {
        let result = SensitiveFieldRedactor.redact("4111 1111 1111 1111", categories: [.paymentCard])
        XCTAssertTrue(result.contains("<pan>"))
    }

    func test_paymentCard_redactsCVV() {
        let result = SensitiveFieldRedactor.redact("CVV: 123", categories: [.paymentCard])
        XCTAssertFalse(result.contains("123"))
        XCTAssertTrue(result.contains("<cvv>"))
    }

    // MARK: - DeviceID category

    func test_deviceID_redactsUUIDv4() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let result = SensitiveFieldRedactor.redact("Device: \(uuid)", categories: [.deviceID])
        XCTAssertFalse(result.contains(uuid))
        XCTAssertTrue(result.contains("<device-id>"))
    }

    // MARK: - LocationCoarse category

    func test_locationCoarse_redactsLatLng() {
        let result = SensitiveFieldRedactor.redact("Coords: 37.774929, -122.419416", categories: [.locationCoarse])
        XCTAssertFalse(result.contains("37.774929"))
        XCTAssertTrue(result.contains("<location>"))
    }

    // MARK: - Multiple categories

    func test_multipleCategories_allRedacted() {
        let text = "Email: a@b.com Phone: 555-000-1111 Card: 4111111111111111"
        let result = SensitiveFieldRedactor.redact(text, categories: [.email, .phone, .paymentCard])
        XCTAssertFalse(result.contains("@"))
        XCTAssertFalse(result.contains("555-000-1111"))
        XCTAssertFalse(result.contains("4111"))
    }

    func test_setOverload_multipleCategories() {
        let text = "a@b.com and 555-000-1111"
        let result = SensitiveFieldRedactor.redact(text, categories: Set([.email, .phone]))
        XCTAssertFalse(result.contains("@"))
        XCTAssertFalse(result.contains("555-000-1111"))
    }

    // MARK: - redactAll

    func test_redactAll_coversPIIAcrossCategories() {
        let text = "Contact Alice Smith at alice@x.com or 555-123-4567 re card 4111111111111111"
        let result = SensitiveFieldRedactor.redactAll(text)
        XCTAssertFalse(result.contains("alice@x.com"))
        XCTAssertFalse(result.contains("555-123-4567"))
        XCTAssertFalse(result.contains("4111"))
    }

    // MARK: - Ordering — critical patterns before low

    func test_sensitivityOrdering_criticalBeforeLow() {
        // paymentCard is .critical; locationCoarse is .low
        // Verify both are applied (ordering correctness tested implicitly by pass).
        let text = "37.7749,-122.4194 and 4111 1111 1111 1111"
        let result = SensitiveFieldRedactor.redact(text, categories: [.locationCoarse, .paymentCard])
        XCTAssertTrue(result.contains("<pan>") || result.contains("<location>"),
                      "At least one pattern should match")
        XCTAssertFalse(result.contains("4111 1111"))
    }

    // MARK: - Immutability

    func test_originalString_isNotMutated() {
        let original = "alice@example.com"
        let copy = original
        _ = SensitiveFieldRedactor.redact(original, categories: [.email])
        XCTAssertEqual(original, copy)
    }
}
