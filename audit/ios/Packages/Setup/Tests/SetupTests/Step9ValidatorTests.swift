import XCTest
@testable import Setup

final class Step9ValidatorTests: XCTestCase {

    // MARK: - validateEmail

    func testValidateEmail_valid_returnsValid() {
        XCTAssertTrue(Step9Validator.validateEmail("alice@example.com").isValid)
    }

    func testValidateEmail_empty_returnsInvalid() {
        let r = Step9Validator.validateEmail("")
        XCTAssertFalse(r.isValid)
        XCTAssertNotNil(r.errorMessage)
    }

    func testValidateEmail_noAt_returnsInvalid() {
        XCTAssertFalse(Step9Validator.validateEmail("notanemail").isValid)
    }

    func testValidateEmail_noTLD_returnsInvalid() {
        XCTAssertFalse(Step9Validator.validateEmail("alice@example").isValid)
    }

    func testValidateEmail_whitespaceOnly_returnsInvalid() {
        XCTAssertFalse(Step9Validator.validateEmail("   ").isValid)
    }

    func testValidateEmail_withLeadingWhitespace_trimsAndValidates() {
        // Leading/trailing spaces are trimmed
        XCTAssertTrue(Step9Validator.validateEmail("  alice@example.com  ").isValid)
    }

    func testValidateEmail_subdomains_valid() {
        XCTAssertTrue(Step9Validator.validateEmail("alice@mail.example.co.uk").isValid)
    }

    // MARK: - validateEmailList

    func testValidateEmailList_empty_valid() {
        let (result, emails) = Step9Validator.validateEmailList("")
        XCTAssertTrue(result.isValid)
        XCTAssertTrue(emails.isEmpty)
    }

    func testValidateEmailList_single_valid() {
        let (result, emails) = Step9Validator.validateEmailList("alice@example.com")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(emails, ["alice@example.com"])
    }

    func testValidateEmailList_commaSeparated_valid() {
        let (result, emails) = Step9Validator.validateEmailList("alice@x.com,bob@x.com")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(emails.count, 2)
    }

    func testValidateEmailList_newlineSeparated_valid() {
        let (result, emails) = Step9Validator.validateEmailList("alice@x.com\nbob@x.com")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(emails.count, 2)
    }

    func testValidateEmailList_duplicate_returnsInvalid() {
        let (result, _) = Step9Validator.validateEmailList("alice@x.com,alice@x.com")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testValidateEmailList_duplicateCaseInsensitive_returnsInvalid() {
        let (result, _) = Step9Validator.validateEmailList("Alice@X.com,alice@x.com")
        XCTAssertFalse(result.isValid)
    }

    func testValidateEmailList_oneBadEmail_returnsInvalid() {
        let (result, _) = Step9Validator.validateEmailList("alice@x.com,notanemail")
        XCTAssertFalse(result.isValid)
    }

    // MARK: - isNextEnabled

    func testIsNextEnabled_empty_returnsTrue() {
        // Zero invitees = skip, still valid
        XCTAssertTrue(Step9Validator.isNextEnabled(raw: ""))
    }

    func testIsNextEnabled_validEmails_returnsTrue() {
        XCTAssertTrue(Step9Validator.isNextEnabled(raw: "a@b.com,c@d.com"))
    }

    func testIsNextEnabled_duplicate_returnsFalse() {
        XCTAssertFalse(Step9Validator.isNextEnabled(raw: "a@b.com,a@b.com"))
    }

    func testIsNextEnabled_badEmail_returnsFalse() {
        XCTAssertFalse(Step9Validator.isNextEnabled(raw: "notanemail"))
    }
}
