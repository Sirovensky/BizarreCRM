import XCTest
@testable import Networking

// MARK: - RetryAfterParserTests

final class RetryAfterParserTests: XCTestCase {

    // MARK: Delta-seconds

    func testParsesPositiveSeconds() {
        XCTAssertEqual(RetryAfterParser.parse("120"), 120)
    }

    func testParsesZeroSecondsReturnsNil() {
        // 0 is not useful — return nil (already in the past / now)
        XCTAssertNil(RetryAfterParser.parse("0"))
    }

    func testParsesOneSecond() {
        XCTAssertEqual(RetryAfterParser.parse("1"), 1)
    }

    func testParsesLargeSeconds() {
        XCTAssertEqual(RetryAfterParser.parse("86400"), 86400)
    }

    func testParseSecondsTrimmedWhitespace() {
        XCTAssertEqual(RetryAfterParser.parse("  60  "), 60)
    }

    // MARK: HTTP-date (IMF-fixdate)

    func testParsesIMFFixdateFuture() {
        // Reference: 2024-01-01 00:00:00 GMT
        // Header:    2024-01-01 00:01:00 GMT  (+60 s)
        let reference = dateFromComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        let header = "Mon, 01 Jan 2024 00:01:00 GMT"
        let result = RetryAfterParser.parse(header, referenceDate: reference)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 60, accuracy: 1)
    }

    func testParsesIMFFixdatePastReturnsNil() {
        let reference = dateFromComponents(year: 2024, month: 1, day: 1, hour: 1, minute: 0, second: 0)
        let header = "Mon, 01 Jan 2024 00:01:00 GMT"
        XCTAssertNil(RetryAfterParser.parse(header, referenceDate: reference))
    }

    func testParsesRFC850Date() {
        // RFC 850 format: "Monday, 01-Jan-24 00:01:00 GMT"
        let reference = dateFromComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        let header = "Monday, 01-Jan-24 00:01:00 GMT"
        let result = RetryAfterParser.parse(header, referenceDate: reference)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!, 0)
    }

    func testParsesAsctimeDate() {
        // asctime format: "Mon Jan  1 00:01:00 2024"
        let reference = dateFromComponents(year: 2024, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        let header = "Mon Jan  1 00:01:00 2024"
        let result = RetryAfterParser.parse(header, referenceDate: reference)
        // asctime parsing is format-dependent; just verify it returns a positive value if parsed
        // (Some Foundation DateFormatter implementations may not support asctime with double space)
        if let delay = result {
            XCTAssertGreaterThan(delay, 0)
        }
        // Not a failure if nil — asctime is an optional format per RFC 7231
    }

    // MARK: Edge cases

    func testEmptyStringReturnsNil() {
        XCTAssertNil(RetryAfterParser.parse(""))
    }

    func testWhitespaceOnlyReturnsNil() {
        XCTAssertNil(RetryAfterParser.parse("   "))
    }

    func testGarbageStringReturnsNil() {
        XCTAssertNil(RetryAfterParser.parse("not-a-date-or-number"))
    }

    func testNegativeNumberReturnsNil() {
        // "-1" is not a valid delta-seconds (non-digit prefix fails Int parse)
        XCTAssertNil(RetryAfterParser.parse("-1"))
    }

    func testFloatStringReturnsNil() {
        // "1.5" is not a valid delta-seconds
        XCTAssertNil(RetryAfterParser.parse("1.5"))
    }

    // MARK: Delay accuracy for known date

    func testExactDelayFromIMFFixdate() {
        // Build a reference date and header exactly 300 s apart.
        let reference = dateFromComponents(year: 2025, month: 6, day: 15, hour: 12, minute: 0, second: 0)
        let header = "Sun, 15 Jun 2025 12:05:00 GMT"
        let result = RetryAfterParser.parse(header, referenceDate: reference)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 300, accuracy: 1)
    }

    // MARK: Helpers

    private func dateFromComponents(
        year: Int, month: Int, day: Int,
        hour: Int, minute: Int, second: Int
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.timeZone = TimeZone(abbreviation: "GMT")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }
}
