import XCTest
@testable import Pos

/// §16.10 — Tests for `ShiftHandoffPolicy` presets and derived logic.
/// Pure value-type logic — no UIKit required.
final class ShiftHandoffPolicyTests: XCTestCase {

    // MARK: - Preset: default

    func test_default_doesNotRequireCount() {
        XCTAssertFalse(ShiftHandoffPolicy.default.requiresCount)
    }

    func test_default_canSkipWithManagerPin() {
        XCTAssertTrue(ShiftHandoffPolicy.default.canSkipWithManagerPin)
    }

    // MARK: - Preset: strict

    func test_strict_requiresCount() {
        XCTAssertTrue(ShiftHandoffPolicy.strict.requiresCount)
    }

    func test_strict_canSkipWithManagerPin() {
        XCTAssertTrue(ShiftHandoffPolicy.strict.canSkipWithManagerPin)
    }

    // MARK: - Preset: mandatory

    func test_mandatory_requiresCount() {
        XCTAssertTrue(ShiftHandoffPolicy.mandatory.requiresCount)
    }

    func test_mandatory_cannotSkipWithManagerPin() {
        XCTAssertFalse(ShiftHandoffPolicy.mandatory.canSkipWithManagerPin)
    }

    // MARK: - Custom init

    func test_customInit_setsFields() {
        let p = ShiftHandoffPolicy(requiresCount: true, canSkipWithManagerPin: false)
        XCTAssertTrue(p.requiresCount)
        XCTAssertFalse(p.canSkipWithManagerPin)
    }

    // MARK: - Equatable

    func test_equatable_sameValues_equal() {
        let a = ShiftHandoffPolicy(requiresCount: true, canSkipWithManagerPin: true)
        let b = ShiftHandoffPolicy(requiresCount: true, canSkipWithManagerPin: true)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentValues_notEqual() {
        XCTAssertNotEqual(ShiftHandoffPolicy.strict, ShiftHandoffPolicy.mandatory)
    }
}
