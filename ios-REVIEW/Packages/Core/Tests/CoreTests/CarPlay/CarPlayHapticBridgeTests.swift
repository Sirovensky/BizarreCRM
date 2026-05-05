#if canImport(CarPlay)
import XCTest
@testable import Core

// MARK: - CarPlayHapticEventTests

/// Tests the ``CarPlayHapticEvent`` enum's value equality.
///
/// ``CarPlayHapticBridge`` itself wraps UIKit side-effects and is not
/// unit-testable in isolation, but the event enum that drives it is a plain
/// value type and is fully verifiable here.
final class CarPlayHapticEventTests: XCTestCase {

    // MARK: Equatable

    func test_selectionConfirmed_equalsItself() {
        XCTAssertEqual(CarPlayHapticEvent.selectionConfirmed, .selectionConfirmed)
    }

    func test_notificationArrived_equalsItself() {
        XCTAssertEqual(CarPlayHapticEvent.notificationArrived, .notificationArrived)
    }

    func test_actionFailed_equalsItself() {
        XCTAssertEqual(CarPlayHapticEvent.actionFailed, .actionFailed)
    }

    func test_selectionConfirmed_notEqualToNotificationArrived() {
        XCTAssertNotEqual(CarPlayHapticEvent.selectionConfirmed, .notificationArrived)
    }

    func test_notificationArrived_notEqualToActionFailed() {
        XCTAssertNotEqual(CarPlayHapticEvent.notificationArrived, .actionFailed)
    }

    func test_actionFailed_notEqualToSelectionConfirmed() {
        XCTAssertNotEqual(CarPlayHapticEvent.actionFailed, .selectionConfirmed)
    }

    // MARK: Exhaustiveness — all cases are reachable

    func test_allCasesDistinct() {
        let all: [CarPlayHapticEvent] = [
            .selectionConfirmed,
            .notificationArrived,
            .actionFailed
        ]
        // Verify the set has no collisions (relies on Equatable).
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() where i != j {
                XCTAssertNotEqual(a, b, "Cases at \(i) and \(j) should differ")
            }
        }
    }

    // MARK: Shared instance

    func test_sharedInstance_isSameObject() {
        let a = CarPlayHapticBridge.shared
        let b = CarPlayHapticBridge.shared
        XCTAssertTrue(a === b)
    }

    // MARK: trigger — smoke tests (no crash)

    /// Verifies that `trigger` does not crash on any legal event.
    /// UIKit haptic side-effects are not observable in unit tests, but the
    /// call must not throw or trap.
    func test_trigger_selectionConfirmed_doesNotCrash() {
        XCTAssertNoThrow(CarPlayHapticBridge.shared.trigger(.selectionConfirmed))
    }

    func test_trigger_notificationArrived_doesNotCrash() {
        XCTAssertNoThrow(CarPlayHapticBridge.shared.trigger(.notificationArrived))
    }

    func test_trigger_actionFailed_doesNotCrash() {
        XCTAssertNoThrow(CarPlayHapticBridge.shared.trigger(.actionFailed))
    }
}

#endif // canImport(CarPlay)
