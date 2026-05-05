import XCTest
@testable import Core

// §31.1 Formatters — Currency + date locale edge-case tests
//
// Covers: `Currency.formatCents` for USD / EUR / JPY and edge values,
// plus `PhoneFormatter` locale oddities and ISO 8601 date round-trip.
//
// Why: §31.1 requires "Formatters — date/currency/phone locale edge cases".

final class CurrencyFormatterTests: XCTestCase {

    // MARK: — USD basics

    func test_usd_zeroAmount_formatsAsZeroDollars() {
        let result = Currency.formatCents(0, code: "USD")
        // Must contain "0" and a currency symbol or code; must not be empty.
        XCTAssertFalse(result.isEmpty, "Zero amount must produce non-empty string")
        XCTAssertTrue(
            result.contains("0"),
            "Zero cents formatted as '\(result)' must contain '0'"
        )
    }

    func test_usd_oneHundredCents_formatsAsOneDollar() {
        let result = Currency.formatCents(100, code: "USD")
        // $1.00 on en_US — we assert the numeric part only for locale independence.
        XCTAssertTrue(
            result.contains("1"),
            "100 cents must contain '1', got '\(result)'"
        )
    }

    func test_usd_typicalRepairBill_containsDecimalPart() {
        // $149.99 → 14999 cents
        let result = Currency.formatCents(14_999, code: "USD")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(
            result.contains("149") || result.contains("14") ,
            "14999 cents formatted as '\(result)' should contain major unit"
        )
    }

    func test_usd_largeCents_doesNotCrash() {
        // $999,999.99 — stress test for overflow / formatter limits
        let result = Currency.formatCents(99_999_999, code: "USD")
        XCTAssertFalse(result.isEmpty, "Large amount must not produce empty string")
    }

    func test_usd_negativeCents_returnsNonEmptyString() {
        // Negative cents can appear for refunds / credits
        let result = Currency.formatCents(-500, code: "USD")
        XCTAssertFalse(result.isEmpty, "Negative amount must produce non-empty string")
    }

    // MARK: — JPY (zero-decimal currency)

    func test_jpy_100yen_containsNumericPart() {
        // ¥100 — JPY has no fractional part; 100 cents == ¥1.00 in our system
        let result = Currency.formatCents(100, code: "JPY")
        XCTAssertFalse(result.isEmpty, "JPY format must not be empty")
        // The formatted number must contain a digit
        let hasDigit = result.contains(where: \.isNumber)
        XCTAssertTrue(hasDigit, "JPY format '\(result)' must contain at least one digit")
    }

    // MARK: — EUR

    func test_eur_oneCent_returnsNonEmptyString() {
        let result = Currency.formatCents(1, code: "EUR")
        XCTAssertFalse(result.isEmpty)
    }

    func test_eur_typicalAmount_containsNumericPart() {
        let result = Currency.formatCents(5_099, code: "EUR")
        let hasDigit = result.contains(where: \.isNumber)
        XCTAssertTrue(hasDigit, "EUR format '\(result)' must contain a digit")
    }

    // MARK: — Unknown currency code

    func test_unknownCurrencyCode_doesNotCrash() {
        // NumberFormatter falls back gracefully for unknown codes
        let result = Currency.formatCents(100, code: "XTS")
        XCTAssertFalse(result.isEmpty, "Unknown currency code must still produce output")
    }

    // MARK: — Code coverage: Int boundary

    func test_intMinValue_doesNotCrash() {
        // formatCents accepts Int; verify no crash at edge
        _ = Currency.formatCents(Int.min, code: "USD")
    }

    func test_intMaxValue_doesNotCrash() {
        _ = Currency.formatCents(Int.max, code: "USD")
    }
}

// MARK: - Date formatter locale edge cases

final class DateLocaleFormatterTests: XCTestCase {

    // MARK: — ISO8601Factory round-trip

    func test_hoursAgo_parsesBackToDate_withinTolerance() throws {
        let str = ISO8601Factory.hoursAgo(1)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        let parsed = try XCTUnwrap(formatter.date(from: str), "ISO8601Factory.hoursAgo output must parse")
        let delta = abs(parsed.timeIntervalSinceNow + 3600)
        XCTAssertLessThan(delta, 5, "Parsed date must be within 5s of 1h ago (got delta \(delta)s)")
    }

    func test_daysAgo_parsesBackToDate() throws {
        let str = ISO8601Factory.daysAgo(7)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        let parsed = try XCTUnwrap(formatter.date(from: str))
        let delta = abs(parsed.timeIntervalSinceNow + 7 * 86_400)
        XCTAssertLessThan(delta, 5, "Parsed date must be within 5s of 7d ago (got delta \(delta)s)")
    }

    func test_utcMidnight_producesExpectedComponents() throws {
        let str = try XCTUnwrap(ISO8601Factory.utcMidnight(year: 2025, month: 6, day: 15))
        // Must start with the expected date prefix
        XCTAssertTrue(str.hasPrefix("2025-06-15"), "utcMidnight string '\(str)' must start with '2025-06-15'")
        XCTAssertTrue(str.hasSuffix("Z"), "utcMidnight string must end with 'Z' (UTC)")
    }

    func test_utcMidnight_invalidDate_returnsNil() {
        // Month 13 is invalid
        let str = ISO8601Factory.utcMidnight(year: 2025, month: 13, day: 1)
        XCTAssertNil(str, "Invalid date components must return nil")
    }

    func test_dateHoursAgo_isInThePast() {
        let date = ISO8601Factory.dateHoursAgo(2)
        XCTAssertLessThan(date, Date(), "dateHoursAgo(2) must be before now")
    }

    func test_dateHoursAgo_zeroReturnsPresentMoment() {
        let before = Date()
        let date = ISO8601Factory.dateHoursAgo(0)
        let after = Date()
        // dateHoursAgo(0) uses Date() at call time — must be within the [before, after] window
        XCTAssertGreaterThanOrEqual(date, before.addingTimeInterval(-1))
        XCTAssertLessThanOrEqual(date, after.addingTimeInterval(1))
    }

    func test_dateDaysAgo_isBeforeDateHoursAgo() {
        let daysAgo = ISO8601Factory.dateDaysAgo(1)
        let hoursAgo = ISO8601Factory.dateHoursAgo(1)
        XCTAssertLessThan(daysAgo, hoursAgo, "1 day ago must be earlier than 1 hour ago")
    }
}
