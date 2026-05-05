// Core/Tests/CoreTests/Localization/PluralFormatTests.swift
//
// §27 i18n tests — PluralFormat helper signatures and key constants.
//
// NOTE: Full plural resolution requires a populated .stringsdict in the test
// bundle, which is not present in a pure Swift Package test target.  These
// tests therefore verify:
//   1. The key constants are non-empty and stable.
//   2. `string(key:count:)` falls back gracefully when no .stringsdict is
//      present (returns the key string — NSLocalizedString fallback behaviour).
//   3. The `String.pluralised` extension delegate correctly to PluralFormat.
//   4. `string(key:values:)` handles zero, singular, and large plural counts
//      without crashing.

import XCTest
@testable import Core

final class PluralFormatTests: XCTestCase {

    // MARK: - Key constants

    func test_pluralKey_items_isNonEmpty() {
        XCTAssertFalse(PluralFormat.PluralKeys.items.isEmpty)
    }

    func test_pluralKey_results_isNonEmpty() {
        XCTAssertFalse(PluralFormat.PluralKeys.results.isEmpty)
    }

    func test_pluralKey_tickets_isNonEmpty() {
        XCTAssertFalse(PluralFormat.PluralKeys.tickets.isEmpty)
    }

    func test_pluralKey_days_isNonEmpty() {
        XCTAssertFalse(PluralFormat.PluralKeys.days.isEmpty)
    }

    // MARK: - Graceful fallback (no stringsdict in test bundle)

    /// When no `.stringsdict` is present, `NSLocalizedString` returns the key.
    /// `String.localizedStringWithFormat` then substitutes `%d` if the format
    /// contains it, or just returns the key.  Either way the result must be
    /// non-empty and must not crash.

    func test_string_itemsKey_count0_doesNotCrash() {
        let result = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 0)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_itemsKey_count1_doesNotCrash() {
        let result = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 1)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_itemsKey_count999_doesNotCrash() {
        let result = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 999)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_ticketsKey_count1_doesNotCrash() {
        let result = PluralFormat.tickets(count: 1)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_daysKey_count7_doesNotCrash() {
        let result = PluralFormat.days(count: 7)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_resultsKey_count0_doesNotCrash() {
        let result = PluralFormat.results(count: 0)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - String extension

    func test_stringExtension_pluralised_delegatesToPluralFormat() {
        let viaExtension  = PluralFormat.PluralKeys.items.pluralised(count: 5)
        let viaDirectCall = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 5)
        XCTAssertEqual(viaExtension, viaDirectCall,
            "pluralised() extension should produce the same result as PluralFormat.string()")
    }

    func test_stringExtension_arbitraryKey_doesNotCrash() {
        let result = "some.nonexistent.key".pluralised(count: 3)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Bundle parameter

    func test_string_mainBundle_doesNotCrash() {
        let result = PluralFormat.string(
            key: PluralFormat.PluralKeys.items,
            count: 2,
            bundle: .main
        )
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Determinism

    func test_string_deterministicForSameCount() {
        let a = PluralFormat.string(key: PluralFormat.PluralKeys.tickets, count: 42)
        let b = PluralFormat.string(key: PluralFormat.PluralKeys.tickets, count: 42)
        XCTAssertEqual(a, b, "Same key/count should always return the same string")
    }

    func test_string_differentCounts_mayDiffer() {
        // Can only assert neither crashes; values may be identical in fallback mode.
        let singular = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 1)
        let plural   = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: 2)
        XCTAssertFalse(singular.isEmpty)
        XCTAssertFalse(plural.isEmpty)
    }

    // MARK: - Negative / boundary

    func test_string_negativeCount_doesNotCrash() {
        let result = PluralFormat.string(key: PluralFormat.PluralKeys.days, count: -1)
        XCTAssertFalse(result.isEmpty)
    }

    func test_string_intMaxCount_doesNotCrash() {
        let result = PluralFormat.string(key: PluralFormat.PluralKeys.items, count: Int.max)
        XCTAssertFalse(result.isEmpty)
    }
}
