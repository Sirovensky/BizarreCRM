import XCTest
@testable import Setup

final class Step4ValidatorTests: XCTestCase {

    // MARK: - Timezone

    func testValidTimezone_returnsValid() {
        let result = Step4Validator.validateTimezone("America/New_York")
        XCTAssertTrue(result.isValid)
    }

    func testEmptyTimezone_returnsInvalid() {
        let result = Step4Validator.validateTimezone("")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testWhitespaceTimezone_returnsInvalid() {
        let result = Step4Validator.validateTimezone("   ")
        XCTAssertFalse(result.isValid)
    }

    func testUnknownTimezone_returnsInvalid() {
        let result = Step4Validator.validateTimezone("Mars/Olympus")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testAllKnownTimezones_returnValid() {
        // Spot check 5 known identifiers
        let samples = ["UTC", "America/Chicago", "Europe/London", "Asia/Tokyo", "Australia/Sydney"]
        for tz in samples {
            XCTAssertTrue(Step4Validator.validateTimezone(tz).isValid, "Expected \(tz) to be valid")
        }
    }

    // MARK: - Currency

    func testValidCurrency_USD_returnsValid() {
        XCTAssertTrue(Step4Validator.validateCurrency("USD").isValid)
    }

    func testValidCurrency_EUR_returnsValid() {
        XCTAssertTrue(Step4Validator.validateCurrency("EUR").isValid)
    }

    func testEmptyCurrency_returnsInvalid() {
        let result = Step4Validator.validateCurrency("")
        XCTAssertFalse(result.isValid)
    }

    func testLowercaseCurrency_returnsInvalid() {
        let result = Step4Validator.validateCurrency("usd")
        XCTAssertFalse(result.isValid)
    }

    func testTwoLetterCurrency_returnsInvalid() {
        XCTAssertFalse(Step4Validator.validateCurrency("US").isValid)
    }

    func testFourLetterCurrency_returnsInvalid() {
        XCTAssertFalse(Step4Validator.validateCurrency("USDT").isValid)
    }

    func testAllMVPCurrencies_returnValid() {
        let mvp = ["USD", "EUR", "GBP", "CAD", "AUD", "JPY", "INR", "PKR", "BRL", "MXN"]
        for code in mvp {
            XCTAssertTrue(Step4Validator.validateCurrency(code).isValid, "\(code) should be valid")
        }
    }

    // MARK: - Locale

    func testValidLocale_enUS_returnsValid() {
        XCTAssertTrue(Step4Validator.validateLocale("en_US").isValid)
    }

    func testEmptyLocale_returnsInvalid() {
        XCTAssertFalse(Step4Validator.validateLocale("").isValid)
    }

    // MARK: - isNextEnabled aggregate

    func testIsNextEnabled_allValid_returnsTrue() {
        let result = Step4Validator.isNextEnabled(
            timezone: "America/New_York",
            currency: "USD",
            locale: "en_US"
        )
        XCTAssertTrue(result)
    }

    func testIsNextEnabled_invalidTimezone_returnsFalse() {
        XCTAssertFalse(Step4Validator.isNextEnabled(
            timezone: "",
            currency: "USD",
            locale: "en_US"
        ))
    }

    func testIsNextEnabled_invalidCurrency_returnsFalse() {
        XCTAssertFalse(Step4Validator.isNextEnabled(
            timezone: "America/New_York",
            currency: "",
            locale: "en_US"
        ))
    }

    func testIsNextEnabled_invalidLocale_returnsFalse() {
        XCTAssertFalse(Step4Validator.isNextEnabled(
            timezone: "America/New_York",
            currency: "USD",
            locale: ""
        ))
    }
}
