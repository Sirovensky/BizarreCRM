import XCTest
@testable import Networking

// MARK: - PinningPolicyTests
//
// Unit tests for PinningPolicy value type (§1.2 TLS Pinning).
// Coverage target: ≥ 80% of PinningPolicy.swift

final class PinningPolicyTests: XCTestCase {

    // MARK: - Initialisation defaults

    func testDefaultAllowBackupIfPinsEmptyIsTrue() {
        let policy = PinningPolicy(pins: [])
        XCTAssertTrue(policy.allowBackupIfPinsEmpty)
    }

    func testDefaultFailClosedIsTrue() {
        let policy = PinningPolicy(pins: [])
        XCTAssertTrue(policy.failClosed)
    }

    func testPinsStoredCorrectly() {
        let pin = Data(repeating: 0xAB, count: 32)
        let policy = PinningPolicy(pins: [pin])
        XCTAssertEqual(policy.pins, [pin])
    }

    func testCustomFlagsStored() {
        let policy = PinningPolicy(
            pins: [],
            allowBackupIfPinsEmpty: false,
            failClosed: false
        )
        XCTAssertFalse(policy.allowBackupIfPinsEmpty)
        XCTAssertFalse(policy.failClosed)
    }

    // MARK: - Equatable

    func testEqualPoliciesAreEqual() {
        let pin = Data(repeating: 0x01, count: 32)
        let a = PinningPolicy(pins: [pin], allowBackupIfPinsEmpty: true, failClosed: true)
        let b = PinningPolicy(pins: [pin], allowBackupIfPinsEmpty: true, failClosed: true)
        XCTAssertEqual(a, b)
    }

    func testDifferentPinsAreNotEqual() {
        let a = PinningPolicy(pins: [Data(repeating: 0x01, count: 32)])
        let b = PinningPolicy(pins: [Data(repeating: 0x02, count: 32)])
        XCTAssertNotEqual(a, b)
    }

    func testDifferentFlagsAreNotEqual() {
        let a = PinningPolicy(pins: [], allowBackupIfPinsEmpty: true, failClosed: true)
        let b = PinningPolicy(pins: [], allowBackupIfPinsEmpty: false, failClosed: true)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Static convenience

    func testNoPinningPolicyHasEmptyPins() {
        XCTAssertTrue(PinningPolicy.noPinning.pins.isEmpty)
    }

    func testNoPinningAllowsBackup() {
        XCTAssertTrue(PinningPolicy.noPinning.allowBackupIfPinsEmpty)
    }

    func testNoPinningIsNotFailClosed() {
        XCTAssertFalse(PinningPolicy.noPinning.failClosed)
    }

    // MARK: - Immutability

    func testMultiplePinsStoredAsSet() {
        // Duplicate pins should be deduplicated by the Set.
        let pin = Data(repeating: 0xCC, count: 32)
        let policy = PinningPolicy(pins: [pin, pin])
        XCTAssertEqual(policy.pins.count, 1)
    }
}
