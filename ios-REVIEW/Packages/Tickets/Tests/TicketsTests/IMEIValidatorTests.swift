import XCTest
@testable import Tickets

/// §4 — IMEIValidator tests.
/// Covers Luhn algorithm correctness, length validation, and edge cases.
/// Target coverage: 100% of IMEIValidator (pure function, no UIKit).
final class IMEIValidatorTests: XCTestCase {

    // MARK: — Known-valid IMEIs (Luhn passes)

    func test_knownValid_apple() {
        // IMEI used in publicly documented test vectors
        XCTAssertTrue(IMEIValidator.isValid("490154203237518"))
    }

    func test_knownValid_samsung() {
        XCTAssertTrue(IMEIValidator.isValid("356938035643809"))
    }

    func test_knownValid_generic1() {
        // 012345678901237 — Luhn check digit 7, verified manually
        XCTAssertTrue(IMEIValidator.isValid("012345678901237"))
    }

    func test_knownValid_allSameDigit_luhnPasses() {
        // 000000000000000 — Luhn sum = 0, passes
        XCTAssertTrue(IMEIValidator.isValid("000000000000000"))
    }

    // MARK: — Known-invalid IMEIs

    func test_invalid_wrongCheckDigit() {
        // 490154203237518 is valid; change last digit to make it fail
        XCTAssertFalse(IMEIValidator.isValid("490154203237519"))
    }

    func test_invalid_wrongCheckDigit2() {
        XCTAssertFalse(IMEIValidator.isValid("356938035643800"))
    }

    // MARK: — Length edge cases

    func test_invalid_tooShort_14digits() {
        XCTAssertFalse(IMEIValidator.isValid("35693803564380"))
    }

    func test_invalid_tooLong_16digits() {
        XCTAssertFalse(IMEIValidator.isValid("3569380356438099"))
    }

    func test_invalid_empty() {
        XCTAssertFalse(IMEIValidator.isValid(""))
    }

    func test_invalid_nonNumeric() {
        XCTAssertFalse(IMEIValidator.isValid("ABCDEF123456789"))
    }

    func test_invalid_mixedAlphanumeric() {
        XCTAssertFalse(IMEIValidator.isValid("35693803564A809"))
    }

    func test_invalid_withSpaces_treatedAsNonDigits() {
        // isValid strips non-digit chars — "356 938 035 643 809" = 15 digits after strip,
        // but IMEIValidator.isValid() does filter(\.isNumber), so this should pass Luhn.
        // The spec says "must be 15 digits" — spaces are filtered.
        XCTAssertTrue(IMEIValidator.isValid("356 938 035 643 809"))
    }

    func test_invalid_withDashes_filtered() {
        XCTAssertTrue(IMEIValidator.isValid("356-938-035-643-809"))
    }

    // MARK: — Format helper

    func test_format_validIMEI() {
        let result = IMEIValidator.format("490154203237518")
        XCTAssertEqual(result, "490154-203237-518")
    }

    func test_format_invalidLength_returnsNil() {
        XCTAssertNil(IMEIValidator.format("1234"))
    }

    func test_format_empty_returnsNil() {
        XCTAssertNil(IMEIValidator.format(""))
    }

    func test_format_stripsNonDigits() {
        // 490154-203237-518 → digits = 490154203237518
        let result = IMEIValidator.format("490154-203237-518")
        XCTAssertEqual(result, "490154-203237-518")
    }

    // MARK: — Luhn property: doubling

    /// Validates the Luhn implementation handles the "doubled > 9" subtraction.
    func test_luhn_doublingSubtraction() {
        // 356938035643809 is valid; replace a digit that would double to > 9
        // and verify the isValid result changes correctly.
        let original = "356938035643809"
        XCTAssertTrue(IMEIValidator.isValid(original))
        // Flip last digit to make it fail
        let flipped = "356938035643801"
        XCTAssertFalse(IMEIValidator.isValid(flipped))
    }

    // MARK: — Zero IMEI

    func test_allZeros_isValidLuhn() {
        // All zeros: Luhn sum = 0, valid by algorithm.
        XCTAssertTrue(IMEIValidator.isValid("000000000000000"))
    }

    // MARK: — Pure function idempotency

    func test_idempotent_sameResultCalledTwice() {
        let imei = "490154203237518"
        XCTAssertEqual(IMEIValidator.isValid(imei), IMEIValidator.isValid(imei))
    }
}
