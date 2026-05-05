import XCTest
@testable import Voice

/// §42.2 — `CallQuickAction.cleanPhoneNumber` tests.
///
/// `placeCall(to:)` is not testable in the Swift Package test host (no
/// UIApplication), but the cleaning logic is fully exercised here.
final class CallQuickActionTests: XCTestCase {

    // MARK: - Basic cleaning

    func test_clean_formattedUSNumber() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("(555) 123-4567"), "5551234567")
    }

    func test_clean_stripsSpacesAndDashes() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("555-123-4567"), "5551234567")
    }

    func test_clean_plainDigitsPassThrough() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("5551234567"), "5551234567")
    }

    func test_clean_internationalPlusPreserved() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("+1-415-555-1212"), "+14155551212")
    }

    func test_clean_elevnDigitUSStripsLeadingOne() {
        // "1 (800) 555-0100" = 11 digits starting with 1 → strip to 10
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("1 (800) 555-0100"), "8005550100")
    }

    func test_clean_tenDigitStartingWithOneNotStripped() {
        // "1555123456" = 10 digits → keep as-is (not 11 digits, so no strip)
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("1555123456"), "1555123456")
    }

    func test_clean_emptyStringReturnsEmpty() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber(""), "")
    }

    func test_clean_nonDigitsOnlyReturnsEmpty() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("no digits here"), "")
    }

    func test_clean_withParenthesesAndDots() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("555.123.4567"), "5551234567")
    }

    func test_clean_ukNumberWithPlus() {
        // UK number — leading + preserved, digits only after
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("+44 20 7946 0958"), "+442079460958")
    }

    func test_clean_singleDigitNotStripped() {
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("1"), "1")
    }

    func test_clean_elevenDigitNotStartingWithOneKept() {
        // 11 digits but starts with 2 → no strip
        XCTAssertEqual(CallQuickAction.cleanPhoneNumber("20987654321"), "20987654321")
    }
}
