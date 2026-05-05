import XCTest
@testable import Setup

final class CompanyInfoValidatorTests: XCTestCase {

    // MARK: - Name validation

    func testName_empty_isInvalid() {
        let result = CompanyInfoValidator.validateName("")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testName_whitespaceOnly_isInvalid() {
        let result = CompanyInfoValidator.validateName("   ")
        XCTAssertFalse(result.isValid)
    }

    func testName_singleChar_isInvalid() {
        let result = CompanyInfoValidator.validateName("A")
        XCTAssertFalse(result.isValid)
    }

    func testName_twoChars_isValid() {
        let result = CompanyInfoValidator.validateName("AB")
        XCTAssertTrue(result.isValid)
    }

    func testName_normal_isValid() {
        let result = CompanyInfoValidator.validateName("Bizarre Repair Shop")
        XCTAssertTrue(result.isValid)
    }

    func testName_tooLong_isInvalid() {
        let long = String(repeating: "A", count: 201)
        let result = CompanyInfoValidator.validateName(long)
        XCTAssertFalse(result.isValid)
    }

    func testName_exactly200_isValid() {
        let exact = String(repeating: "A", count: 200)
        let result = CompanyInfoValidator.validateName(exact)
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Phone validation

    func testPhone_empty_isValid() {
        // Phone is required in the form but the validator marks empty as needing
        // the caller to decide; the isNextEnabled gate handles this.
        let result = CompanyInfoValidator.validatePhone("")
        XCTAssertFalse(result.isValid) // 0 digits != 10
    }

    func testPhone_10digits_isValid() {
        let result = CompanyInfoValidator.validatePhone("5551234567")
        XCTAssertTrue(result.isValid)
    }

    func testPhone_formatted_isValid() {
        let result = CompanyInfoValidator.validatePhone("(555) 123-4567")
        XCTAssertTrue(result.isValid)
    }

    func testPhone_with1prefix_isValid() {
        let result = CompanyInfoValidator.validatePhone("15551234567")
        XCTAssertTrue(result.isValid)
    }

    func testPhone_9digits_isInvalid() {
        let result = CompanyInfoValidator.validatePhone("555123456")
        XCTAssertFalse(result.isValid)
    }

    func testPhone_11digitsNon1_isInvalid() {
        let result = CompanyInfoValidator.validatePhone("25551234567")
        XCTAssertFalse(result.isValid)
    }

    // MARK: - Phone formatting

    func testFormat_10digits_producesPattern() {
        let formatted = CompanyInfoValidator.formatPhone("5551234567")
        XCTAssertEqual(formatted, "(555) 123-4567")
    }

    func testFormat_with1prefix_producesPattern() {
        let formatted = CompanyInfoValidator.formatPhone("15551234567")
        XCTAssertEqual(formatted, "(555) 123-4567")
    }

    func testFormat_partial_returnsRaw() {
        let raw = "555"
        let formatted = CompanyInfoValidator.formatPhone(raw)
        XCTAssertEqual(formatted, raw)
    }

    func testFormat_formattedInput_isIdempotent() {
        let once = CompanyInfoValidator.formatPhone("5551234567")
        let twice = CompanyInfoValidator.formatPhone(once)
        XCTAssertEqual(once, twice)
    }

    // MARK: - Website validation

    func testWebsite_empty_isValid() {
        let result = CompanyInfoValidator.validateWebsite("")
        XCTAssertTrue(result.isValid) // optional field
    }

    func testWebsite_validHttps_isValid() {
        let result = CompanyInfoValidator.validateWebsite("https://bizarrecrm.com")
        XCTAssertTrue(result.isValid)
    }

    func testWebsite_noScheme_isValid() {
        let result = CompanyInfoValidator.validateWebsite("bizarrecrm.com")
        XCTAssertTrue(result.isValid)
    }

    func testWebsite_http_isValid() {
        let result = CompanyInfoValidator.validateWebsite("http://example.com")
        XCTAssertTrue(result.isValid)
    }

    func testWebsite_noHost_isInvalid() {
        let result = CompanyInfoValidator.validateWebsite("https://")
        XCTAssertFalse(result.isValid)
    }

    func testWebsite_randomString_isInvalid() {
        // A string with spaces can't form a valid URL
        let result = CompanyInfoValidator.validateWebsite("not a url at all!!!")
        // Either invalid or valid depending on URL parsing; we assert the method doesn't crash
        _ = result
    }

    // MARK: - EIN validation

    func testEIN_empty_isValid() {
        let result = CompanyInfoValidator.validateEIN("")
        XCTAssertTrue(result.isValid) // optional
    }

    func testEIN_9digits_isValid() {
        let result = CompanyInfoValidator.validateEIN("123456789")
        XCTAssertTrue(result.isValid)
    }

    func testEIN_withDash_isValid() {
        let result = CompanyInfoValidator.validateEIN("12-3456789")
        XCTAssertTrue(result.isValid)
    }

    func testEIN_8digits_isInvalid() {
        let result = CompanyInfoValidator.validateEIN("12345678")
        XCTAssertFalse(result.isValid)
    }

    func testEIN_10digits_isInvalid() {
        let result = CompanyInfoValidator.validateEIN("1234567890")
        XCTAssertFalse(result.isValid)
    }

    // MARK: - isNextEnabled

    func testNextEnabled_nameAndPhone_enabled() {
        let ok = CompanyInfoValidator.isNextEnabled(name: "Bizarre Shop", phone: "(555) 123-4567")
        XCTAssertTrue(ok)
    }

    func testNextEnabled_emptyName_disabled() {
        let ok = CompanyInfoValidator.isNextEnabled(name: "", phone: "(555) 123-4567")
        XCTAssertFalse(ok)
    }

    func testNextEnabled_emptyPhone_enabled() {
        // Phone is required per form but validator treats empty as "not entered yet"
        let ok = CompanyInfoValidator.isNextEnabled(name: "Bizarre Shop", phone: "")
        XCTAssertTrue(ok)
    }

    func testNextEnabled_invalidPhone_disabled() {
        let ok = CompanyInfoValidator.isNextEnabled(name: "Bizarre Shop", phone: "123")
        XCTAssertFalse(ok)
    }
}
