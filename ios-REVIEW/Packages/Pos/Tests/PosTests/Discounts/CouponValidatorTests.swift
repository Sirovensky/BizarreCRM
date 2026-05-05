import XCTest
@testable import Pos

/// Tests for `CouponValidator`.
/// Covers: format rules (length, character set), expiry gate, exhaustion gate,
/// nil-expiry (unlimited), format-only convenience overload.
final class CouponValidatorTests: XCTestCase {

    private let validator = CouponValidator()

    // MARK: - Format: valid codes

    func test_validAlphanumericCode_returnsValid() {
        XCTAssertTrue(validator.validate(rawCode: "SAVE20").isValid)
    }

    func test_validCodeWithHyphen_returnsValid() {
        XCTAssertTrue(validator.validate(rawCode: "PROMO-2024").isValid)
    }

    func test_validCodeWithUnderscore_returnsValid() {
        XCTAssertTrue(validator.validate(rawCode: "VIP_TIER1").isValid)
    }

    func test_minLengthCode_returnsValid() {
        // Exactly minCodeLength characters
        let code = String(repeating: "A", count: CouponValidator.minCodeLength)
        XCTAssertTrue(validator.validate(rawCode: code).isValid)
    }

    func test_maxLengthCode_returnsValid() {
        let code = String(repeating: "X", count: CouponValidator.maxCodeLength)
        XCTAssertTrue(validator.validate(rawCode: code).isValid)
    }

    func test_mixedCaseCode_isTreatedByCaller_validFormat() {
        // Validator does NOT auto-uppercase — caller is expected to do so.
        // But lowercase letters are still alphanumeric and pass format check.
        XCTAssertTrue(validator.validate(rawCode: "save20").isValid)
    }

    func test_leadingTrailingWhitespace_isTrimmed_returnsValid() {
        XCTAssertTrue(validator.validate(rawCode: "  SAVE20  ").isValid)
    }

    // MARK: - Format: too short

    func test_emptyCode_returnsInvalidFormat() {
        let result = validator.validate(rawCode: "")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for empty code, got \(result)") }
    }

    func test_tooShortCode_returnsInvalidFormat() {
        // One less than minCodeLength
        let code = String(repeating: "A", count: CouponValidator.minCodeLength - 1)
        let result = validator.validate(rawCode: code)
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat, got \(result)") }
    }

    func test_whitespaceOnlyCode_returnsInvalidFormat() {
        let result = validator.validate(rawCode: "   ")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for whitespace-only input") }
    }

    // MARK: - Format: too long

    func test_tooLongCode_returnsInvalidFormat() {
        let code = String(repeating: "A", count: CouponValidator.maxCodeLength + 1)
        let result = validator.validate(rawCode: code)
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for oversized code, got \(result)") }
    }

    // MARK: - Format: illegal characters

    func test_spaceInCode_returnsInvalidFormat() {
        let result = validator.validate(rawCode: "SAVE 20")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for code with space") }
    }

    func test_specialCharsInCode_returnsInvalidFormat() {
        let result = validator.validate(rawCode: "SAVE@20!")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for code with @/!") }
    }

    func test_dollarSignInCode_returnsInvalidFormat() {
        let result = validator.validate(rawCode: "$SAVE20")
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat for code with $") }
    }

    // MARK: - Expiry gate

    func test_expiredCoupon_returnsExpired() {
        let past = Date(timeIntervalSinceNow: -86_400)
        let coupon = CouponCode(id: "1", code: "OLD", ruleId: "r", ruleName: "10%", expiresAt: past)
        let result = validator.validate(rawCode: "OLD", knownCoupon: coupon)
        if case .expired = result { XCTAssert(true) }
        else { XCTFail("Expected .expired, got \(result)") }
    }

    func test_expiredCoupon_errorMessage_containsDate() {
        let past = Date(timeIntervalSinceNow: -86_400)
        let coupon = CouponCode(id: "1", code: "OLD", ruleId: "r", ruleName: "10%", expiresAt: past)
        let result = validator.validate(rawCode: "OLD", knownCoupon: coupon)
        XCTAssertNotNil(result.errorMessage)
    }

    func test_futureExpiringCoupon_returnsValid() {
        let future = Date(timeIntervalSinceNow: 86_400)
        let coupon = CouponCode(id: "1", code: "NEW", ruleId: "r", ruleName: "10%", expiresAt: future)
        let result = validator.validate(rawCode: "NEW", knownCoupon: coupon)
        XCTAssertTrue(result.isValid)
    }

    func test_noExpiryCoupon_returnsValid() {
        let coupon = CouponCode(id: "1", code: "FOREVER", ruleId: "r", ruleName: "10%", expiresAt: nil)
        let result = validator.validate(rawCode: "FOREVER", knownCoupon: coupon)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Exhaustion gate

    func test_exhaustedCoupon_returnsExhausted() {
        let coupon = CouponCode(id: "1", code: "USED", ruleId: "r", ruleName: "10%", usesRemaining: 0)
        let result = validator.validate(rawCode: "USED", knownCoupon: coupon)
        if case .exhausted = result { XCTAssert(true) }
        else { XCTFail("Expected .exhausted, got \(result)") }
    }

    func test_exhaustedCoupon_errorMessage_isNonEmpty() {
        let coupon = CouponCode(id: "1", code: "USED", ruleId: "r", ruleName: "10%", usesRemaining: 0)
        let result = validator.validate(rawCode: "USED", knownCoupon: coupon)
        XCTAssertFalse(result.errorMessage?.isEmpty ?? true)
    }

    func test_couponWithRemainingUses_returnsValid() {
        let coupon = CouponCode(id: "1", code: "STILL", ruleId: "r", ruleName: "10%", usesRemaining: 5)
        let result = validator.validate(rawCode: "STILL", knownCoupon: coupon)
        XCTAssertTrue(result.isValid)
    }

    func test_couponWithUnlimitedUses_returnsValid() {
        let coupon = CouponCode(id: "1", code: "OPEN", ruleId: "r", ruleName: "10%", usesRemaining: nil)
        let result = validator.validate(rawCode: "OPEN", knownCoupon: coupon)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Expiry takes priority over exhaustion

    func test_expiredAndExhausted_returnsExpiredFirst() {
        let past = Date(timeIntervalSinceNow: -86_400)
        let coupon = CouponCode(id: "1", code: "BOTH", ruleId: "r", ruleName: "10%",
                                usesRemaining: 0, expiresAt: past)
        let result = validator.validate(rawCode: "BOTH", knownCoupon: coupon)
        if case .expired = result { XCTAssert(true) }
        else { XCTFail("Expected .expired to take priority, got \(result)") }
    }

    // MARK: - Format-only convenience

    func test_validateFormat_validCode_returnsValid() {
        XCTAssertTrue(validator.validateFormat("SUMMER25").isValid)
    }

    func test_validateFormat_invalidCode_returnsInvalidFormat() {
        let result = validator.validateFormat("AB")   // too short
        if case .invalidFormat = result { XCTAssert(true) }
        else { XCTFail("Expected invalidFormat, got \(result)") }
    }

    // MARK: - Error message helper

    func test_validResult_errorMessage_isNil() {
        XCTAssertNil(CouponValidationResult.valid.errorMessage)
    }

    func test_invalidFormat_errorMessage_isNonNil() {
        XCTAssertNotNil(CouponValidationResult.invalidFormat("too short").errorMessage)
    }

    func test_exhausted_errorMessage_isNonNil() {
        XCTAssertNotNil(CouponValidationResult.exhausted.errorMessage)
    }
}
