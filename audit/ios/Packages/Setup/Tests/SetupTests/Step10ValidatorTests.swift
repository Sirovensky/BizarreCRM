import XCTest
@testable import Setup

final class Step10ValidatorTests: XCTestCase {

    // MARK: - validateFromNumber — skip provider

    func testValidateFromNumber_skipProvider_alwaysValid() {
        XCTAssertTrue(Step10Validator.validateFromNumber("", provider: .skip).isValid)
        XCTAssertTrue(Step10Validator.validateFromNumber("   ", provider: .skip).isValid)
    }

    // MARK: - validateFromNumber — non-skip providers

    func testValidateFromNumber_twilio_nonEmpty_valid() {
        XCTAssertTrue(Step10Validator.validateFromNumber("+15005550006", provider: .twilio).isValid)
    }

    func testValidateFromNumber_twilio_empty_invalid() {
        let r = Step10Validator.validateFromNumber("", provider: .twilio)
        XCTAssertFalse(r.isValid)
        XCTAssertNotNil(r.errorMessage)
    }

    func testValidateFromNumber_twilio_whitespaceOnly_invalid() {
        XCTAssertFalse(Step10Validator.validateFromNumber("   ", provider: .twilio).isValid)
    }

    func testValidateFromNumber_managed_nonEmpty_valid() {
        XCTAssertTrue(Step10Validator.validateFromNumber("+15005550006", provider: .managed).isValid)
    }

    func testValidateFromNumber_managed_empty_invalid() {
        XCTAssertFalse(Step10Validator.validateFromNumber("", provider: .managed).isValid)
    }

    func testValidateFromNumber_bandwidth_nonEmpty_valid() {
        XCTAssertTrue(Step10Validator.validateFromNumber("+12025551234", provider: .bandwidth).isValid)
    }

    func testValidateFromNumber_bandwidth_empty_invalid() {
        XCTAssertFalse(Step10Validator.validateFromNumber("", provider: .bandwidth).isValid)
    }

    // MARK: - isNextEnabled

    func testIsNextEnabled_skipProvider_noNumber_true() {
        XCTAssertTrue(Step10Validator.isNextEnabled(fromNumber: "", provider: .skip))
    }

    func testIsNextEnabled_twilioWithNumber_true() {
        XCTAssertTrue(Step10Validator.isNextEnabled(fromNumber: "+15555555555", provider: .twilio))
    }

    func testIsNextEnabled_twilioNoNumber_false() {
        XCTAssertFalse(Step10Validator.isNextEnabled(fromNumber: "", provider: .twilio))
    }

    func testIsNextEnabled_managedNoNumber_false() {
        XCTAssertFalse(Step10Validator.isNextEnabled(fromNumber: "", provider: .managed))
    }

    func testIsNextEnabled_bandwidthNoNumber_false() {
        XCTAssertFalse(Step10Validator.isNextEnabled(fromNumber: "", provider: .bandwidth))
    }
}
