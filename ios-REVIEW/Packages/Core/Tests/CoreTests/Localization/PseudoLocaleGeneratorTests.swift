// Core/Tests/CoreTests/Localization/PseudoLocaleGeneratorTests.swift
//
// §27 i18n tests — PseudoLocaleGenerator expansion ratio and wrapping behaviour.
//
// NOTE: PseudoLocaleGenerator is conditionally compiled; in DEBUG builds
// (which is what `swift test` uses by default) the full logic runs.  In
// Release builds, `wrap` is a no-op and `expansionRatio` returns 1.0.
// These tests are written to pass in both builds.

import XCTest
@testable import Core

final class PseudoLocaleGeneratorTests: XCTestCase {

    // MARK: - Wrapping behaviour (DEBUG)

    func test_wrap_emptyString_returnsPrefixAndSuffix() {
        let result = PseudoLocaleGenerator.wrap("")
#if DEBUG
        // Empty content → still prefix+suffix present
        XCTAssertTrue(result.hasPrefix(PseudoLocaleGenerator.prefix),
            "Wrapped empty string should start with prefix, got: \(result)")
        XCTAssertTrue(result.hasSuffix(PseudoLocaleGenerator.suffix),
            "Wrapped empty string should end with suffix, got: \(result)")
#else
        XCTAssertEqual(result, "", "Release: wrap should be a no-op on empty string")
#endif
    }

    func test_wrap_singleWord_containsOriginalLength() {
        let input  = "Save"
        let result = PseudoLocaleGenerator.wrap(input)
#if DEBUG
        XCTAssertTrue(result.hasPrefix(PseudoLocaleGenerator.prefix),
            "Wrapped string should start with '\(PseudoLocaleGenerator.prefix)'")
        XCTAssertTrue(result.hasSuffix(PseudoLocaleGenerator.suffix),
            "Wrapped string should end with '\(PseudoLocaleGenerator.suffix)'")
        // Original characters should be replaced, so wrapped length > input length
        XCTAssertGreaterThan(result.count, input.count,
            "Wrapped string should be longer than input")
#else
        XCTAssertEqual(result, input, "Release: wrap should return unchanged string")
#endif
    }

    func test_wrap_multiWord_hasPrefix() {
        let input  = "Delete this item"
        let result = PseudoLocaleGenerator.wrap(input)
#if DEBUG
        XCTAssertTrue(result.hasPrefix(PseudoLocaleGenerator.prefix))
        XCTAssertTrue(result.hasSuffix(PseudoLocaleGenerator.suffix))
#else
        XCTAssertEqual(result, input)
#endif
    }

    // MARK: - Expansion ratio

    func test_expansionRatio_emptyString_isOne() {
        let ratio = PseudoLocaleGenerator.expansionRatio(for: "")
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
    }

    func test_expansionRatio_singleWord_isAtLeast130Percent() {
        let ratio = PseudoLocaleGenerator.expansionRatio(for: "Save")
#if DEBUG
        XCTAssertGreaterThanOrEqual(ratio, 1.3,
            "Wrapped 'Save' should expand by at least 30%, got ratio: \(ratio)")
#else
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001, "Release: no expansion")
#endif
    }

    func test_expansionRatio_longerString_isAtLeast120Percent() {
        // Longer strings have the prefix/suffix overhead amortised, but each
        // character may also expand (multi-byte diacritics).
        let input = "This is a longer sentence for truncation testing"
        let ratio = PseudoLocaleGenerator.expansionRatio(for: input)
#if DEBUG
        XCTAssertGreaterThanOrEqual(ratio, 1.2,
            "Longer wrapped string should expand by at least 20%, got ratio: \(ratio)")
#else
        XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
#endif
    }

    func test_expansionRatio_fourLocaleStrings_allExpanded() {
        // Simulate strings as they'd appear after L10n lookup.
        // These are typical UI label lengths in each language.
        let samples = [
            "en_US: Save",
            "fr_FR: Enregistrer",
            "ar_SA: حفظ",       // Arabic — may have less diacritic mapping (pass-through)
            "ja_JP: 保存",       // Japanese — CJK pass-through
        ]
        for sample in samples {
            let ratio = PseudoLocaleGenerator.expansionRatio(for: sample)
#if DEBUG
            // Even if non-ASCII chars pass through, prefix+suffix ensure > 1.0
            XCTAssertGreaterThan(ratio, 1.0,
                "'\(sample)' should expand > 1.0x, got: \(ratio)")
#else
            XCTAssertEqual(ratio, 1.0, accuracy: 0.001)
#endif
        }
    }

    // MARK: - Dictionary wrapping

    func test_wrapDictionary_preservesKeys() {
        let input = ["action.save": "Save", "action.cancel": "Cancel"]
        let result = PseudoLocaleGenerator.wrap(dictionary: input)
        XCTAssertEqual(Set(result.keys), Set(input.keys),
            "Wrapped dictionary should have same keys as input")
    }

    func test_wrapDictionary_valuesAreWrapped() {
        let input = ["key1": "Hello", "key2": "World"]
        let result = PseudoLocaleGenerator.wrap(dictionary: input)
#if DEBUG
        for (key, value) in result {
            XCTAssertTrue(value.hasPrefix(PseudoLocaleGenerator.prefix),
                "Value for '\(key)' should have prefix, got: \(value)")
        }
#else
        XCTAssertEqual(result, input)
#endif
    }

    func test_wrapDictionary_emptyDictionary_returnsEmpty() {
        let result = PseudoLocaleGenerator.wrap(dictionary: [:])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Idempotency / determinism

    func test_wrap_sameInput_sameTwoOutputs() {
        let a = PseudoLocaleGenerator.wrap("Consistent")
        let b = PseudoLocaleGenerator.wrap("Consistent")
        XCTAssertEqual(a, b, "wrap() should be deterministic")
    }

    // MARK: - Prefix / suffix constants

    func test_prefixAndSuffix_areNonEmpty() {
        XCTAssertFalse(PseudoLocaleGenerator.prefix.isEmpty)
        XCTAssertFalse(PseudoLocaleGenerator.suffix.isEmpty)
    }
}
