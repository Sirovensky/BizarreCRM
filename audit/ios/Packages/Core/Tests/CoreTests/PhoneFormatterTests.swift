import XCTest
@testable import Core

final class PhoneFormatterTests: XCTestCase {
    func test_format_tenDigitUS() {
        XCTAssertEqual(PhoneFormatter.format("5551234567"), "+1 (555)-123-4567")
    }

    func test_format_elevenDigitWithLeadingOne() {
        XCTAssertEqual(PhoneFormatter.format("15551234567"), "+1 (555)-123-4567")
    }

    func test_format_passesThroughUnknown() {
        XCTAssertEqual(PhoneFormatter.format("abc"), "abc")
    }

    func test_normalize_tenDigitGetsE164() {
        XCTAssertEqual(PhoneFormatter.normalize("(555) 123-4567"), "+15551234567")
    }
}
