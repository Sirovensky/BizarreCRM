// Tests for FieldLocationPolicy — pure enum/helper logic.
// No CLLocationManager required; uses MockCLLocationManager.
//
// `CLAuthorizationStatus.authorizedWhenInUse` is unavailable on macOS,
// so tests using it are guarded with `#if os(iOS)`.

import XCTest
import CoreLocation
@testable import FieldService

final class FieldLocationPolicyTests: XCTestCase {

    // MARK: - requestPermissionIfNeeded

    @MainActor
    func test_requestPermission_notDetermined_requestsWhenInUse() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .notDetermined
        FieldLocationPolicy.requestPermissionIfNeeded(manager: manager, role: .standard)
        XCTAssertTrue(manager.requestedWhenInUse)
        XCTAssertFalse(manager.requestedAlways)
    }

    @MainActor
    func test_requestPermission_denied_doesNothing() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .denied
        FieldLocationPolicy.requestPermissionIfNeeded(manager: manager, role: .fieldService)
        XCTAssertFalse(manager.requestedAlways)
        XCTAssertFalse(manager.requestedWhenInUse)
    }

    @MainActor
    func test_requestPermission_alreadyAlways_doesNothing() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedAlways
        FieldLocationPolicy.requestPermissionIfNeeded(manager: manager, role: .fieldService)
        XCTAssertFalse(manager.requestedAlways)
        XCTAssertFalse(manager.requestedWhenInUse)
    }

    #if os(iOS)
    @MainActor
    func test_requestPermission_whenInUseAndFieldRole_requestsAlways() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        FieldLocationPolicy.requestPermissionIfNeeded(manager: manager, role: .fieldService)
        XCTAssertTrue(manager.requestedAlways)
        XCTAssertFalse(manager.requestedWhenInUse)
    }

    @MainActor
    func test_requestPermission_whenInUseAndStandardRole_doesNotStepUp() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        FieldLocationPolicy.requestPermissionIfNeeded(manager: manager, role: .standard)
        XCTAssertFalse(manager.requestedAlways)
        XCTAssertFalse(manager.requestedWhenInUse)
    }
    #endif

    // MARK: - desiredAccuracy

    func test_accuracy_duringActiveJob_isBest() {
        XCTAssertEqual(
            FieldLocationPolicy.desiredAccuracy(duringActiveJob: true),
            kCLLocationAccuracyBest
        )
    }

    func test_accuracy_notActiveJob_isHundredMeters() {
        XCTAssertEqual(
            FieldLocationPolicy.desiredAccuracy(duringActiveJob: false),
            kCLLocationAccuracyHundredMeters
        )
    }

    // MARK: - handleBackgrounded

    @MainActor
    func test_backgrounded_notActiveJob_stopsUpdating() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedAlways
        FieldLocationPolicy.handleBackgrounded(manager: manager, duringActiveJob: false)
        XCTAssertTrue(manager.stoppedUpdating)
        XCTAssertFalse(manager.startedSignificant)
    }

    @MainActor
    func test_backgrounded_activeJobAlwaysGranted_switchesToSignificant() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedAlways
        FieldLocationPolicy.handleBackgrounded(manager: manager, duringActiveJob: true)
        XCTAssertTrue(manager.stoppedUpdating)
        XCTAssertTrue(manager.startedSignificant)
    }

    #if os(iOS)
    @MainActor
    func test_backgrounded_activeJobWhenInUseOnly_stopsUpdating() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedWhenInUse
        FieldLocationPolicy.handleBackgrounded(manager: manager, duringActiveJob: true)
        XCTAssertTrue(manager.stoppedUpdating)
        XCTAssertFalse(manager.startedSignificant)
    }
    #endif

    // MARK: - handleForegrounded

    @MainActor
    func test_foregrounded_activeJob_resumesGPS() {
        let manager = MockCLLocationManager()
        manager.authorizationStatus = .authorizedAlways
        FieldLocationPolicy.handleForegrounded(manager: manager, duringActiveJob: true)
        XCTAssertTrue(manager.stoppedSignificant)
        XCTAssertTrue(manager.startedUpdating)
    }

    @MainActor
    func test_foregrounded_noActiveJob_doesNothing() {
        let manager = MockCLLocationManager()
        FieldLocationPolicy.handleForegrounded(manager: manager, duringActiveJob: false)
        XCTAssertFalse(manager.startedUpdating)
    }

    // MARK: - isWithinCheckInRange

    func test_within100m_returnsTrue() {
        XCTAssertTrue(FieldLocationPolicy.isWithinCheckInRange(distanceMeters: 50))
        XCTAssertTrue(FieldLocationPolicy.isWithinCheckInRange(distanceMeters: 99.9))
    }

    func test_exactly100m_returnsFalse() {
        XCTAssertFalse(FieldLocationPolicy.isWithinCheckInRange(distanceMeters: 100))
    }

    func test_beyond100m_returnsFalse() {
        XCTAssertFalse(FieldLocationPolicy.isWithinCheckInRange(distanceMeters: 150))
        XCTAssertFalse(FieldLocationPolicy.isWithinCheckInRange(distanceMeters: 500))
    }
}
