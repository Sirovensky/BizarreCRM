import XCTest
@testable import Setup

final class Step8ValidatorTests: XCTestCase {

    // MARK: - validateName

    func testValidateName_nonEmpty_returnsValid() {
        XCTAssertTrue(Step8Validator.validateName("Main Street Shop").isValid)
    }

    func testValidateName_empty_returnsInvalid() {
        let result = Step8Validator.validateName("")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidateName_whitespaceOnly_returnsInvalid() {
        XCTAssertFalse(Step8Validator.validateName("   ").isValid)
    }

    // MARK: - validateAddress

    func testValidateAddress_nonEmpty_returnsValid() {
        XCTAssertTrue(Step8Validator.validateAddress("123 Main St, Springfield").isValid)
    }

    func testValidateAddress_empty_returnsInvalid() {
        let result = Step8Validator.validateAddress("")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidateAddress_whitespaceOnly_returnsInvalid() {
        XCTAssertFalse(Step8Validator.validateAddress("   ").isValid)
    }

    // MARK: - isNextEnabled

    func testIsNextEnabled_bothFilled_returnsTrue() {
        XCTAssertTrue(Step8Validator.isNextEnabled(name: "HQ", address: "1 Main St"))
    }

    func testIsNextEnabled_emptyName_returnsFalse() {
        XCTAssertFalse(Step8Validator.isNextEnabled(name: "", address: "1 Main St"))
    }

    func testIsNextEnabled_emptyAddress_returnsFalse() {
        XCTAssertFalse(Step8Validator.isNextEnabled(name: "HQ", address: ""))
    }

    func testIsNextEnabled_bothEmpty_returnsFalse() {
        XCTAssertFalse(Step8Validator.isNextEnabled(name: "", address: ""))
    }
}
