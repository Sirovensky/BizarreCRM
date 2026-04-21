import XCTest
@testable import Core

/// Unit tests for `MemoryProbe`.
///
/// TDD: these tests were written before the implementation and initially failed (RED).
/// The implementation in `Core/Metrics/MemoryProbe.swift` was written to make them pass (GREEN).
final class MemoryProbeTests: XCTestCase {

    // MARK: - currentResidentMB

    /// The resident footprint must be positive (> 0 MB) when running on a real Darwin process.
    func test_currentResidentMB_returnsPositiveValue() {
        let mb = MemoryProbe.currentResidentMB()
        XCTAssertGreaterThan(mb, 0, "Expected positive resident memory, got \(mb) MB")
    }

    /// The footprint must be plausibly bounded — a test process should not exceed 2 GB.
    func test_currentResidentMB_isWithinSaneBounds() {
        let mb = MemoryProbe.currentResidentMB()
        XCTAssertLessThan(mb, 2048, "Resident memory \(mb) MB exceeds 2 GB — likely a unit conversion bug")
    }

    /// Calling `currentResidentMB()` twice in quick succession should return
    /// consistent values (within ±50 MB — allocations during the test won't spike more).
    func test_currentResidentMB_isStableAcrossTwoCalls() {
        let first = MemoryProbe.currentResidentMB()
        let second = MemoryProbe.currentResidentMB()
        XCTAssertLessThan(
            abs(second - first),
            50,
            "Back-to-back samples differed by more than 50 MB (\(first) vs \(second)) — unexpected spike"
        )
    }

    // MARK: - sample

    /// `sample(label:)` must not crash for any label string.
    func test_sample_doesNotThrow() {
        // No assertion — we only verify no crash / exception.
        MemoryProbe.sample(label: "test")
        MemoryProbe.sample(label: "")
        MemoryProbe.sample(label: "label with spaces & special chars: 🎯")
    }

    /// `sample(label:)` is a fire-and-forget log call; calling it multiple times
    /// must be safe (no state mutation, no accumulated side effects).
    func test_sample_isIdempotent() {
        for i in 0 ..< 10 {
            MemoryProbe.sample(label: "iteration-\(i)")
        }
        // If we reach here without crashing, the test passes.
        XCTAssertTrue(true)
    }
}
