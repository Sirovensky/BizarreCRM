// Core/Tests/CoreTests/Localization/FormatStylesTests.swift
//
// §27.2 tests for FormatStyle-based locale formatters:
// dateTime, Decimal currency, integer/double number, percent, distance, relative.

import XCTest
@testable import Core

@available(iOS 15.0, macOS 12.0, *)
final class FormatStylesTests: XCTestCase {

    private let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 23
        c.hour = 12;   c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    // MARK: Date.FormatStyle.dateTime

    func testFormatDateTime_enUS_containsYear() {
        let s = LocaleFormatter.enUS.formatDateTime(referenceDate) {
            $0.day().month(.abbreviated).year()
        }
        XCTAssertTrue(s.contains("2026"))
    }

    func testFormatDateTime_frFR_usesFrenchMonth() {
        let s = LocaleFormatter.frFR.formatDateTime(referenceDate) {
            $0.day().month(.wide).year()
        }
        XCTAssertTrue(s.lowercased().contains("avril"))
    }

    // MARK: Decimal.FormatStyle.Currency

    func testFormatDecimalCurrency_USD() {
        let s = LocaleFormatter.enUS.formatCurrency(Decimal(string: "1999.99")!, currencyCode: "USD")
        XCTAssertTrue(s.contains("1,999.99"))
        XCTAssertTrue(s.contains("$"))
    }

    func testFormatDecimalCurrency_EUR_inFrance() {
        let s = LocaleFormatter.frFR.formatCurrency(Decimal(string: "1999.99")!, currencyCode: "EUR")
        XCTAssertTrue(s.contains("€"))
    }

    // MARK: Number FormatStyle

    func testFormatInt_enUS_groupingSeparator() {
        XCTAssertEqual(LocaleFormatter.enUS.formatNumber(12345), "12,345")
    }

    func testFormatDouble_frFR_decimalComma() {
        let s = LocaleFormatter.frFR.formatNumber(12_345.6, fractionDigits: 1...1)
        XCTAssertTrue(s.contains(","))
        XCTAssertFalse(s.hasSuffix("."))
    }

    // MARK: Percent FormatStyle

    func testFormatPercentStyle_enUS() {
        let s = LocaleFormatter.enUS.formatPercentStyle(0.075, fractionDigits: 1)
        XCTAssertTrue(s.contains("7.5"))
        XCTAssertTrue(s.contains("%"))
    }

    // MARK: MeasurementFormatter (distance)

    func testFormatDistance_enUS_usesMiles() {
        let s = LocaleFormatter.enUS.formatDistance(meters: 5_000)
        // en_US natural scale should produce miles for ~3.1 mi.
        XCTAssertTrue(s.lowercased().contains("mi"), "got \(s)")
    }

    func testFormatDistance_frFR_usesKilometers() {
        let s = LocaleFormatter.frFR.formatDistance(meters: 5_000)
        XCTAssertTrue(s.lowercased().contains("km"), "got \(s)")
    }

    // MARK: RelativeDateTimeFormatter

    func testFormatRelative_pastMinute_enUS() {
        let now = referenceDate
        let twoMinAgo = now.addingTimeInterval(-120)
        let s = LocaleFormatter.enUS.formatRelative(twoMinAgo, relativeTo: now)
        // English should include "ago" or "minute".
        XCTAssertTrue(s.lowercased().contains("ago") || s.lowercased().contains("minute"),
                      "got \(s)")
    }

    func testFormatRelative_futureDay_frFR() {
        let now = referenceDate
        let inThreeDays = now.addingTimeInterval(3 * 86_400)
        let s = LocaleFormatter.frFR.formatRelative(inThreeDays, relativeTo: now)
        XCTAssertFalse(s.isEmpty)
    }
}
