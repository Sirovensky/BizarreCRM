import XCTest
@testable import Setup

final class Step6ValidatorTests: XCTestCase {

    // MARK: - validateName

    func testValidateName_nonEmpty_returnsValid() {
        XCTAssertTrue(Step6Validator.validateName("Sales Tax").isValid)
    }

    func testValidateName_empty_returnsInvalid() {
        XCTAssertFalse(Step6Validator.validateName("").isValid)
    }

    func testValidateName_whitespaceOnly_returnsInvalid() {
        XCTAssertFalse(Step6Validator.validateName("   ").isValid)
    }

    func testValidateName_tooLong_returnsInvalid() {
        let longName = String(repeating: "x", count: 101)
        XCTAssertFalse(Step6Validator.validateName(longName).isValid)
    }

    func testValidateName_exactly100_returnsValid() {
        let maxName = String(repeating: "x", count: 100)
        XCTAssertTrue(Step6Validator.validateName(maxName).isValid)
    }

    // MARK: - validateRate

    func testValidateRate_validDecimal_returnsValid() {
        XCTAssertTrue(Step6Validator.validateRate("8.25").isValid)
    }

    func testValidateRate_zero_returnsValid() {
        XCTAssertTrue(Step6Validator.validateRate("0").isValid)
    }

    func testValidateRate_exactlyThirty_returnsValid() {
        XCTAssertTrue(Step6Validator.validateRate("30").isValid)
    }

    func testValidateRate_empty_returnsInvalid() {
        XCTAssertFalse(Step6Validator.validateRate("").isValid)
    }

    func testValidateRate_nonNumeric_returnsInvalid() {
        XCTAssertFalse(Step6Validator.validateRate("abc").isValid)
    }

    func testValidateRate_negative_returnsInvalid() {
        let result = Step6Validator.validateRate("-1")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidateRate_overThirty_returnsInvalid() {
        let result = Step6Validator.validateRate("30.01")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidateRate_integerString_returnsValid() {
        XCTAssertTrue(Step6Validator.validateRate("10").isValid)
    }

    // MARK: - isNextEnabled

    func testIsNextEnabled_validNameAndRate_returnsTrue() {
        XCTAssertTrue(Step6Validator.isNextEnabled(name: "GST", rateText: "5.0"))
    }

    func testIsNextEnabled_emptyName_returnsFalse() {
        XCTAssertFalse(Step6Validator.isNextEnabled(name: "", rateText: "8.25"))
    }

    func testIsNextEnabled_invalidRate_returnsFalse() {
        XCTAssertFalse(Step6Validator.isNextEnabled(name: "Tax", rateText: "31"))
    }
}
