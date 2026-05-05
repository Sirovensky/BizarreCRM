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

    // MARK: - §57 Indoor fallback — positioningSource

    func test_gpsAccuracy_under20m_returnsGPS() {
        // CLLocation with accuracy ≤ 20 → GPS
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .gps)
    }

    func test_gpsAccuracy_exactly20m_returnsGPS() {
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 20,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .gps)
    }

    func test_accuracy_25m_returnsCellAndWifi() {
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .cellAndWifi)
    }

    func test_accuracy_150m_returnsCellAndWifi() {
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 150,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .cellAndWifi)
    }

    func test_accuracy_over200m_returnsUnavailable() {
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: 250,
            verticalAccuracy: 10,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .unavailable)
    }

    func test_negativeAccuracy_returnsUnavailable() {
        let loc = CLLocation(
            coordinate: .init(latitude: 37.0, longitude: -122.0),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        XCTAssertEqual(FieldLocationPolicy.positioningSource(from: loc), .unavailable)
    }

    // MARK: - §57 Indoor fallback — indoorBannerMessage

    func test_bannerMessage_gps_returnsNil() {
        XCTAssertNil(FieldLocationPolicy.indoorBannerMessage(source: .gps))
    }

    func test_bannerMessage_cellAndWifi_returnsBanner() {
        let msg = FieldLocationPolicy.indoorBannerMessage(source: .cellAndWifi)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.contains("approximate"), "Should mention 'approximate' for cell/wifi fallback")
    }

    func test_bannerMessage_unavailable_returnsBanner() {
        let msg = FieldLocationPolicy.indoorBannerMessage(source: .unavailable)
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg!.lowercased().contains("unavailable"), "Should mention 'unavailable'")
    }

    // MARK: - §57 Privacy — FieldLocationPrivacyViewModel CSV builder

    func test_csvBuilder_emptyEntries_returnsHeaderOnly() {
        let csv = FieldLocationPrivacyViewModel.buildCSV(entries: [])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("timestamp"))
    }

    func test_csvBuilder_oneEntry_returnsTwoLines() {
        let entry = FieldLocationHistoryEntry(
            id: 1,
            timestamp: "2026-04-26T10:00:00Z",
            latitude: 37.3318,
            longitude: -122.0312,
            accuracyMeters: 15.0,
            jobId: 42
        )
        let csv = FieldLocationPrivacyViewModel.buildCSV(entries: [entry])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2, "Header + 1 data row")
        XCTAssertTrue(lines[1].contains("37.3318"))
        XCTAssertTrue(lines[1].contains("42"))
    }

    func test_csvBuilder_noJobId_leavesEmptyField() {
        let entry = FieldLocationHistoryEntry(
            id: 2,
            timestamp: "2026-04-26T11:00:00Z",
            latitude: 37.0,
            longitude: -122.0,
            accuracyMeters: 8.0,
            jobId: nil
        )
        let csv = FieldLocationPrivacyViewModel.buildCSV(entries: [entry])
        let dataLine = csv.components(separatedBy: "\n")[1]
        XCTAssertTrue(dataLine.hasSuffix(","), "Last field (job_id) should be empty when nil")
    }
}
