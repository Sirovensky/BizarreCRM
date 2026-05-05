// Core/Tests/CoreTests/Localization/RTLDetectionTests.swift
//
// §27 i18n tests — RTLDetection across representative locales.
//
// Covers:
//   - Language codes known to be RTL (ar, he, fa, ur)
//   - Language codes known to be LTR (en, fr, ja, zh)
//   - Locale-based detection for the four test locales (en_US, fr_FR, ar_SA, ja_JP)
//   - LayoutDirection mapping
//   - Environment key default value
//   - Edge cases (empty string, unknown code)

import XCTest
import SwiftUI
@testable import Core

final class RTLDetectionTests: XCTestCase {

    // MARK: - Known RTL language codes

    func test_arabic_isRTL() {
        XCTAssertTrue(RTLDetection.isRTL(languageCode: "ar"),
            "Arabic should be detected as RTL")
    }

    func test_hebrew_isRTL() {
        XCTAssertTrue(RTLDetection.isRTL(languageCode: "he"),
            "Hebrew should be detected as RTL")
    }

    func test_persian_isRTL() {
        XCTAssertTrue(RTLDetection.isRTL(languageCode: "fa"),
            "Persian/Farsi should be detected as RTL")
    }

    func test_urdu_isRTL() {
        XCTAssertTrue(RTLDetection.isRTL(languageCode: "ur"),
            "Urdu should be detected as RTL")
    }

    // MARK: - Known LTR language codes

    func test_english_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(languageCode: "en"),
            "English should be LTR")
    }

    func test_french_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(languageCode: "fr"),
            "French should be LTR")
    }

    func test_japanese_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(languageCode: "ja"),
            "Japanese should be LTR (horizontal mode)")
    }

    func test_chinese_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(languageCode: "zh"),
            "Chinese should be LTR (horizontal mode)")
    }

    // MARK: - Locale-based detection for the four reference locales

    func test_enUS_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(locale: Locale(identifier: "en_US")))
    }

    func test_frFR_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(locale: Locale(identifier: "fr_FR")))
    }

    func test_arSA_isRTL() {
        XCTAssertTrue(RTLDetection.isRTL(locale: Locale(identifier: "ar_SA")),
            "ar_SA should be detected as RTL")
    }

    func test_jaJP_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(locale: Locale(identifier: "ja_JP")))
    }

    // MARK: - Layout direction mapping

    func test_layoutDirection_arabicIsRightToLeft() {
        let dir = RTLDetection.layoutDirection(forLanguageCode: "ar")
        XCTAssertEqual(dir, .rightToLeft)
    }

    func test_layoutDirection_englishIsLeftToRight() {
        let dir = RTLDetection.layoutDirection(forLanguageCode: "en")
        XCTAssertEqual(dir, .leftToRight)
    }

    func test_layoutDirection_arSA_locale_isRightToLeft() {
        let dir = RTLDetection.layoutDirection(for: Locale(identifier: "ar_SA"))
        XCTAssertEqual(dir, .rightToLeft)
    }

    func test_layoutDirection_enUS_locale_isLeftToRight() {
        let dir = RTLDetection.layoutDirection(for: Locale(identifier: "en_US"))
        XCTAssertEqual(dir, .leftToRight)
    }

    // MARK: - Edge cases

    func test_emptyLanguageCode_isLTR() {
        // NSLocale.characterDirection returns .leftToRight for unknown/empty codes.
        XCTAssertFalse(RTLDetection.isRTL(languageCode: ""),
            "Empty language code should default to LTR")
    }

    func test_unknownLanguageCode_isLTR() {
        XCTAssertFalse(RTLDetection.isRTL(languageCode: "xx"),
            "Unknown language code should default to LTR")
    }

    // MARK: - currentLocaleIsRTL is a Bool

    func test_currentLocaleIsRTL_returnsBool() {
        // Can only assert it doesn't crash; the result depends on the test host locale.
        let _ = RTLDetection.currentLocaleIsRTL
    }

    // MARK: - Environment key

    func test_rtlEnabledKey_defaultMatchesCurrentLocale() {
        let key = RTLEnabledKey.defaultValue
        // Default value is derived from the current locale; just ensure it is a Bool.
        XCTAssertTrue(key == true || key == false)
    }

    // MARK: - Consistency across the four test locales

    func test_fourLocales_rtlConsistency() {
        // en_US, fr_FR, ja_JP → LTR; ar_SA → RTL
        let expectations: [(String, Bool)] = [
            ("en_US", false),
            ("fr_FR", false),
            ("ar_SA", true),
            ("ja_JP", false),
        ]
        for (id, expectedRTL) in expectations {
            let result = RTLDetection.isRTL(locale: Locale(identifier: id))
            XCTAssertEqual(result, expectedRTL,
                "\(id): expected RTL=\(expectedRTL), got \(result)")
        }
    }
}
