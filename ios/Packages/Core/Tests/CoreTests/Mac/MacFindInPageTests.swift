// CoreTests/Mac/MacFindInPageTests.swift
//
// Unit tests for §23.3 MacFindInPageModifier helpers.
// UI behaviour requires a SwiftUI host; the wrap + label helpers carry the
// interesting edge cases.

import XCTest
@testable import Core

final class MacFindInPageTests: XCTestCase {

    // MARK: - wrap

    func test_wrap_emptyCount_returnsZero() {
        XCTAssertEqual(MacFindInPageModifier.wrap(5, count: 0), 0)
        XCTAssertEqual(MacFindInPageModifier.wrap(-3, count: 0), 0)
    }

    func test_wrap_indexEqualsCount_wrapsToZero() {
        XCTAssertEqual(MacFindInPageModifier.wrap(5, count: 5), 0)
    }

    func test_wrap_indexAboveCount_wrapsModulo() {
        XCTAssertEqual(MacFindInPageModifier.wrap(7, count: 5), 2)
        XCTAssertEqual(MacFindInPageModifier.wrap(12, count: 5), 2)
    }

    func test_wrap_negativeIndex_wrapsToTail() {
        XCTAssertEqual(MacFindInPageModifier.wrap(-1, count: 5), 4)
        XCTAssertEqual(MacFindInPageModifier.wrap(-3, count: 5), 2)
    }

    // MARK: - matchLabel

    func test_matchLabel_zeroTotal_isZeroOfZero() {
        XCTAssertEqual(MacFindInPageModifier.matchLabel(current: 0, total: 0), "0 of 0")
    }

    func test_matchLabel_displaysOneBased() {
        XCTAssertEqual(MacFindInPageModifier.matchLabel(current: 0, total: 12), "1 of 12")
        XCTAssertEqual(MacFindInPageModifier.matchLabel(current: 11, total: 12), "12 of 12")
    }
}
