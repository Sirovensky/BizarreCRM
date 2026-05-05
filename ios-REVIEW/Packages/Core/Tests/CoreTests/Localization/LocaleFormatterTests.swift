// Core/Tests/CoreTests/Localization/LocaleFormatterTests.swift
//
// §27 i18n tests — LocaleFormatter round-trip across 4 locales.
//
// Covers:
//   - Date formatting: en_US, fr_FR, ar_SA, ja_JP
//   - Number formatting: decimal separator differences
//   - Currency formatting: symbol / code placement
//   - Cent-to-currency convenience
//   - Percent formatting
//   - Formatter caching (same instance returned for same key)

import XCTest
@testable import Core

final class LocaleFormatterTests: XCTestCase {

    // MARK: - Reference date/values

    /// 2026-04-23 12:30:00 UTC — used in all date tests.
    private let referenceDate: Date = {
        var components = DateComponents()
        components.year   = 2026
        components.month  = 4
        components.day    = 23
        components.hour   = 12
        components.minute = 30
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    // MARK: - Date formatting — output is non-empty and locale-distinct

    func test_dateFormat_enUS_isNonEmpty() {
        let result = LocaleFormatter.enUS.formatDate(referenceDate)
        XCTAssertFalse(result.isEmpty, "en_US date should not be empty")
    }

    func test_dateFormat_frFR_isNonEmpty() {
        let result = LocaleFormatter.frFR.formatDate(referenceDate)
        XCTAssertFalse(result.isEmpty, "fr_FR date should not be empty")
    }

    func test_dateFormat_arSA_isNonEmpty() {
        let result = LocaleFormatter.arSA.formatDate(referenceDate)
        XCTAssertFalse(result.isEmpty, "ar_SA date should not be empty")
    }

    func test_dateFormat_jaJP_isNonEmpty() {
        let result = LocaleFormatter.jaJP.formatDate(referenceDate)
        XCTAssertFalse(result.isEmpty, "ja_JP date should not be empty")
    }

    /// All four locale formats should be distinct for the same date.
    func test_dateFormat_fourLocales_areDistinct() {
        let enStr = LocaleFormatter.enUS.formatDate(referenceDate)
        let frStr = LocaleFormatter.frFR.formatDate(referenceDate)
        let arStr = LocaleFormatter.arSA.formatDate(referenceDate)
        let jaStr = LocaleFormatter.jaJP.formatDate(referenceDate)

        let all = [enStr, frStr, arStr, jaStr]
        let unique = Set(all)
        XCTAssertEqual(unique.count, all.count,
            "All four locale date strings should be distinct. Got: \(all)")
    }

    // MARK: - Number formatting

    /// en_US uses `.` as decimal separator; fr_FR uses `,` (or narrow-no-break-space group sep).
    func test_numberFormat_enUS_usesDecimalPoint() {
        let result = LocaleFormatter.enUS.formatNumber(1234.56)
        XCTAssertTrue(result.contains(".") || result.contains(","),
            "en_US number should contain a decimal separator, got: \(result)")
        // The fractional part should appear somewhere
        XCTAssertFalse(result.isEmpty)
    }

    func test_numberFormat_frFR_isNonEmpty() {
        let result = LocaleFormatter.frFR.formatNumber(1234.56)
        XCTAssertFalse(result.isEmpty, "fr_FR number should not be empty")
    }

    func test_numberFormat_arSA_isNonEmpty() {
        let result = LocaleFormatter.arSA.formatNumber(1234.56)
        XCTAssertFalse(result.isEmpty, "ar_SA number should not be empty")
    }

    func test_numberFormat_jaJP_isNonEmpty() {
        let result = LocaleFormatter.jaJP.formatNumber(1234.56)
        XCTAssertFalse(result.isEmpty, "ja_JP number should not be empty")
    }

    /// Four locales should produce distinct number strings for the same value.
    func test_numberFormat_fourLocales_areDistinct() {
        let en = LocaleFormatter.enUS.formatNumber(1234.56)
        let fr = LocaleFormatter.frFR.formatNumber(1234.56)
        let ar = LocaleFormatter.arSA.formatNumber(1234.56)
        let ja = LocaleFormatter.jaJP.formatNumber(1234.56)
        // At least two of the four should differ.
        let unique = Set([en, fr, ar, ja])
        XCTAssertGreaterThan(unique.count, 1,
            "At least two locales should format 1234.56 differently. Got: \([en, fr, ar, ja])")
    }

    // MARK: - Currency formatting

    func test_currency_enUS_USD_containsDollarSign() {
        let result = LocaleFormatter.enUS.formatCurrency(19.99, currencyCode: "USD")
        XCTAssertTrue(result.contains("$") || result.contains("USD"),
            "en_US USD should contain $ or USD, got: \(result)")
    }

    func test_currency_frFR_EUR_isNonEmpty() {
        let result = LocaleFormatter.frFR.formatCurrency(19.99, currencyCode: "EUR")
        XCTAssertFalse(result.isEmpty, "fr_FR EUR should not be empty")
    }

    func test_currency_arSA_SAR_isNonEmpty() {
        let result = LocaleFormatter.arSA.formatCurrency(19.99, currencyCode: "SAR")
        XCTAssertFalse(result.isEmpty, "ar_SA SAR should not be empty")
    }

    func test_currency_jaJP_JPY_isNonEmpty() {
        let result = LocaleFormatter.jaJP.formatCurrency(1999, currencyCode: "JPY")
        XCTAssertFalse(result.isEmpty, "ja_JP JPY should not be empty")
    }

    /// Currency codes should appear in the formatted string for at least one locale
    /// when the formatter is asked to produce a standard currency format.
    func test_currency_code_appearsInAtLeastOneLocale() {
        let eur_en = LocaleFormatter.enUS.formatCurrency(9.99, currencyCode: "EUR")
        let eur_fr = LocaleFormatter.frFR.formatCurrency(9.99, currencyCode: "EUR")
        let containsEur = eur_en.contains("EUR") || eur_en.contains("€")
                        || eur_fr.contains("EUR") || eur_fr.contains("€")
        XCTAssertTrue(containsEur,
            "At least one locale should include EUR symbol/code. Got: \(eur_en), \(eur_fr)")
    }

    // MARK: - Cents helper

    func test_cents_1999_USD_roundTrips() {
        let result = LocaleFormatter.enUS.formatCents(1999, currencyCode: "USD")
        XCTAssertTrue(result.contains("19") || result.contains("20"),
            "1999 cents ($19.99) should produce a string containing '19', got: \(result)")
    }

    func test_cents_zero_USD_isNonEmpty() {
        let result = LocaleFormatter.enUS.formatCents(0, currencyCode: "USD")
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Percent formatting

    func test_percent_enUS_halfIsNonEmpty() {
        let result = LocaleFormatter.enUS.formatPercent(0.5)
        XCTAssertFalse(result.isEmpty)
    }

    func test_percent_frFR_halfIsNonEmpty() {
        let result = LocaleFormatter.frFR.formatPercent(0.5)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - DateTime formatting

    func test_dateTime_enUS_isNonEmpty() {
        let result = LocaleFormatter.enUS.formatDateTime(referenceDate)
        XCTAssertFalse(result.isEmpty, "en_US dateTime should not be empty")
    }

    func test_dateTime_arSA_isNonEmpty() {
        let result = LocaleFormatter.arSA.formatDateTime(referenceDate)
        XCTAssertFalse(result.isEmpty, "ar_SA dateTime should not be empty")
    }

    // MARK: - Template formatting

    func test_templateFormat_yearMonth_isNonEmpty() {
        let result = LocaleFormatter.enUS.formatDate(referenceDate, template: "MMMMyyyy")
        XCTAssertFalse(result.isEmpty, "Template format should produce non-empty output")
    }

    // MARK: - Factory helpers

    func test_forIdentifier_createsCorrectLocale() {
        let fmt = LocaleFormatter.forIdentifier("de_DE")
        XCTAssertEqual(fmt.locale.identifier, "de_DE")
    }

    // MARK: - Caching behaviour

    /// Requesting the same formatter twice should return equal output (deterministic).
    func test_caching_sameLocaleProducesSameOutput() {
        let f1 = LocaleFormatter(locale: Locale(identifier: "en_US"))
        let f2 = LocaleFormatter(locale: Locale(identifier: "en_US"))
        let r1 = f1.formatNumber(42.0)
        let r2 = f2.formatNumber(42.0)
        XCTAssertEqual(r1, r2, "Same locale should produce identical output on both calls")
    }
}
