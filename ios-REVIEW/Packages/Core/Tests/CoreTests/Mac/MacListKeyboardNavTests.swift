// CoreTests/Mac/MacListKeyboardNavTests.swift
//
// Unit tests for §23.3 MacListKeyboardNavModifier.clamp(_:count:).
// Behavioural test of the modifier itself requires a SwiftUI host; the
// clamp logic carries the interesting edge cases.

import XCTest
@testable import Core

final class MacListKeyboardNavTests: XCTestCase {

    func test_clamp_emptyList_returnsZero() {
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(5, count: 0), 0)
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(-3, count: 0), 0)
    }

    func test_clamp_negativeIndex_clampsToZero() {
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(-1, count: 10), 0)
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(-100, count: 10), 0)
    }

    func test_clamp_indexBeyondCount_clampsToLast() {
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(10, count: 10), 9)
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(99, count: 10), 9)
    }

    func test_clamp_validIndex_returnsAsIs() {
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(0, count: 10), 0)
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(5, count: 10), 5)
        XCTAssertEqual(MacListKeyboardNavModifier.clamp(9, count: 10), 9)
    }
}
