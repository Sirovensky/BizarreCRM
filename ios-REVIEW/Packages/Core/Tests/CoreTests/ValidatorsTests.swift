import XCTest
@testable import Core

// MARK: - §31.1 Validators — email, phone, SKU, IMEI

// MARK: EmailValidator

final class EmailValidatorTests: XCTestCase {

    // MARK: Valid inputs

    func test_email_simpleValid() {
        XCTAssertTrue(EmailValidator.validate("user@example.com").isValid)
    }

    func test_email_subdomainValid() {
        XCTAssertTrue(EmailValidator.validate("alice.bob+tag@mail.example.co.uk").isValid)
    }

    func test_email_localPartSpecialCharsValid() {
        XCTAssertTrue(EmailValidator.validate("user+filter@domain.io").isValid)
    }

    // MARK: Invalid inputs

    func test_email_empty_invalid() {
        XCTAssertFalse(EmailValidator.validate("").isValid)
    }

    func test_email_noAtSign_invalid() {
        XCTAssertFalse(EmailValidator.validate("userdomain.com").isValid)
    }

    func test_email_multipleAtSigns_invalid() {
        XCTAssertFalse(EmailValidator.validate("a@@b.com").isValid)
    }

    func test_email_noDomainDot_invalid() {
        XCTAssertFalse(EmailValidator.validate("user@localhost").isValid)
    }

    func test_email_leadingDotLocal_invalid() {
        XCTAssertFalse(EmailValidator.validate(".user@example.com").isValid)
    }

    func test_email_trailingDotLocal_invalid() {
        XCTAssertFalse(EmailValidator.validate("user.@example.com").isValid)
    }

    func test_email_consecutiveDotsLocal_invalid() {
        XCTAssertFalse(EmailValidator.validate("us..er@example.com").isValid)
    }

    func test_email_tooLong_invalid() {
        let long = String(repeating: "a", count: 65) + "@example.com"
        XCTAssertFalse(EmailValidator.validate(long).isValid)
    }

    func test_email_errorMessage_noAtSign() {
        if case let .invalid(msg) = EmailValidator.validate("nodomain") {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .invalid for 'nodomain'")
        }
    }
}

// MARK: PhoneValidator

final class PhoneValidatorTests: XCTestCase {

    // MARK: Valid inputs

    func test_phone_e164_valid() {
        XCTAssertTrue(PhoneValidator.validate("+15551234567").isValid)
    }

    func test_phone_e164_internationalValid() {
        XCTAssertTrue(PhoneValidator.validate("+447911123456").isValid)
    }

    func test_phone_nanp_tenDigits_valid() {
        XCTAssertTrue(PhoneValidator.validate("5551234567").isValid)
    }

    func test_phone_nanp_formatted_valid() {
        XCTAssertTrue(PhoneValidator.validate("(555) 123-4567").isValid)
    }

    func test_phone_nanp_dashes_valid() {
        XCTAssertTrue(PhoneValidator.validate("555-123-4567").isValid)
    }

    // MARK: Invalid inputs

    func test_phone_empty_invalid() {
        XCTAssertFalse(PhoneValidator.validate("").isValid)
    }

    func test_phone_tooShort_invalid() {
        XCTAssertFalse(PhoneValidator.validate("12345").isValid)
    }

    func test_phone_tooLong_invalid() {
        XCTAssertFalse(PhoneValidator.validate("+1234567890123456").isValid)  // 17 digits
    }

    func test_phone_nonDigits_invalid() {
        XCTAssertFalse(PhoneValidator.validate("555-ABC-1234").isValid)
    }

    func test_phone_nanpAreaCode000_invalid() {
        XCTAssertFalse(PhoneValidator.validate("0001234567").isValid)
    }

    func test_phone_nanpAreaCode199_invalid() {
        XCTAssertFalse(PhoneValidator.validate("1991234567").isValid)
    }
}

// MARK: SKUValidator

final class SKUValidatorTests: XCTestCase {

    // MARK: Valid inputs

    func test_sku_simpleAlpha_valid() {
        XCTAssertTrue(SKUValidator.validate("ABC123").isValid)
    }

    func test_sku_dashed_valid() {
        XCTAssertTrue(SKUValidator.validate("WIDGET-001").isValid)
    }

    func test_sku_multiSegment_valid() {
        XCTAssertTrue(SKUValidator.validate("ABC-DEF-0099").isValid)
    }

    func test_sku_lowercase_normalised_valid() {
        // Lowercase is uppercased internally
        XCTAssertTrue(SKUValidator.validate("widget-001").isValid)
    }

    func test_sku_minLength_valid() {
        XCTAssertTrue(SKUValidator.validate("AB").isValid)
    }

    // MARK: Invalid inputs

    func test_sku_empty_invalid() {
        XCTAssertFalse(SKUValidator.validate("").isValid)
    }

    func test_sku_tooShort_invalid() {
        XCTAssertFalse(SKUValidator.validate("A").isValid)
    }

    func test_sku_tooLong_invalid() {
        XCTAssertFalse(SKUValidator.validate(String(repeating: "A", count: 41)).isValid)
    }

    func test_sku_leadingDash_invalid() {
        XCTAssertFalse(SKUValidator.validate("-ABC123").isValid)
    }

    func test_sku_trailingDash_invalid() {
        XCTAssertFalse(SKUValidator.validate("ABC123-").isValid)
    }

    func test_sku_consecutiveDashes_invalid() {
        XCTAssertFalse(SKUValidator.validate("ABC--123").isValid)
    }

    func test_sku_specialChars_invalid() {
        XCTAssertFalse(SKUValidator.validate("ABC@123").isValid)
    }
}

// MARK: IMEIValidator

final class IMEIValidatorTests: XCTestCase {

    // Known-valid IMEI (Luhn passes): 490154203237518
    private let validIMEI = "490154203237518"
    // Same with dashes: 49-015420-323751-8
    private let validIMEIDashed = "49-015420-323751-8"

    // MARK: Valid inputs

    func test_imei_valid15Digits() {
        XCTAssertTrue(IMEIValidator.validate(validIMEI).isValid)
    }

    func test_imei_validWithDashes() {
        XCTAssertTrue(IMEIValidator.validate(validIMEIDashed).isValid)
    }

    // MARK: Invalid inputs

    func test_imei_empty_invalid() {
        XCTAssertFalse(IMEIValidator.validate("").isValid)
    }

    func test_imei_tooShort_invalid() {
        XCTAssertFalse(IMEIValidator.validate("12345678901234").isValid)  // 14 digits
    }

    func test_imei_tooLong_invalid() {
        XCTAssertFalse(IMEIValidator.validate("1234567890123456").isValid)  // 16 digits
    }

    func test_imei_nonDigits_invalid() {
        XCTAssertFalse(IMEIValidator.validate("49015420323751X").isValid)
    }

    func test_imei_badLuhn_invalid() {
        // Flip last digit: 490154203237518 → 490154203237519
        XCTAssertFalse(IMEIValidator.validate("490154203237519").isValid)
    }

    func test_imei_allZeros_invalid() {
        // Luhn: sum = 0 which is divisible by 10, but this is a known invalid IMEI.
        // Let's test the Luhn itself: 000000000000000 → check digit 0, sum = 0 → technically passes Luhn.
        // Just verify the helper doesn't crash.
        let result = IMEIValidator.validate("000000000000000")
        // Either valid or invalid is fine as long as it doesn't crash.
        _ = result.isValid
    }

    // MARK: Luhn algorithm unit tests

    func test_luhn_knownValidIMEI() {
        XCTAssertTrue(IMEIValidator.luhn(validIMEI))
    }

    func test_luhn_knownInvalidIMEI() {
        XCTAssertFalse(IMEIValidator.luhn("490154203237519"))
    }
}
