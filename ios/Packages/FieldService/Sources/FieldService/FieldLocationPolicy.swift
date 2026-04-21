// §57 FieldLocationPolicy — pure location permission + power policy helper.
//
// Location always requires the `com.apple.developer.location.push` entitlement
// for background delivery. `NSLocationAlwaysAndWhenInUseUsageDescription` must
// be added to Info.plist (via scripts/write-info-plist.sh) before requesting
// `.authorizedAlways`. NSLocationWhenInUseUsageDescription is already present.
//
// DO NOT request `.authorizedAlways` for non-field users — privacy policy.

import Foundation
import CoreLocation

// MARK: - CLLocationManagerProtocol

/// Abstraction over CLLocationManager for testability.
public protocol CLLocationManagerProtocol: AnyObject, Sendable {
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
    func requestAlwaysAuthorization()
    func startUpdatingLocation()
    func stopUpdatingLocation()
    func startMonitoringSignificantLocationChanges()
    func stopMonitoringSignificantLocationChanges()
}

extension CLLocationManager: CLLocationManagerProtocol {}

// MARK: - UserRole

public enum FieldUserRole: String, Sendable {
    case fieldService
    case standard
}

// MARK: - FieldLocationPolicy

/// §57 — Location permission and power policy for field-service technicians.
///
/// Rules:
/// - Always ask `whenInUse` first; never jump straight to `always`.
/// - Step up to `always` **only** when user has `.fieldService` role.
/// - Accuracy: approximate by default; precise only during active job.
/// - Power: significant-location-change while backgrounded; stop raw
///   GPS on foreground-leave unless `.always` was granted.
public enum FieldLocationPolicy: Sendable {

    // MARK: - Permission

    /// Request `whenInUse` if not already determined. Caller must call
    /// from the main thread (CLLocationManager requirement).
    @MainActor
    public static func requestPermissionIfNeeded(
        manager: CLLocationManagerProtocol,
        role: FieldUserRole
    ) {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse where role == .fieldService:
            // Step up to always only for field techs who need background geofence.
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - Accuracy

    /// Desired accuracy for a given context.
    public static func desiredAccuracy(duringActiveJob: Bool) -> CLLocationAccuracy {
        duringActiveJob ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
    }

    // MARK: - Power management

    /// Called when app moves to background. Switches to low-power
    /// significant-change updates (unless `.always` not granted).
    @MainActor
    public static func handleBackgrounded(
        manager: CLLocationManagerProtocol,
        duringActiveJob: Bool
    ) {
        guard duringActiveJob else {
            manager.stopUpdatingLocation()
            return
        }
        let status = manager.authorizationStatus
        if status == .authorizedAlways {
            manager.stopUpdatingLocation()
            manager.startMonitoringSignificantLocationChanges()
        } else {
            // Only whenInUse — must stop; background updates not permitted.
            manager.stopUpdatingLocation()
        }
    }

    /// Called when app returns to foreground during an active job.
    @MainActor
    public static func handleForegrounded(
        manager: CLLocationManagerProtocol,
        duringActiveJob: Bool
    ) {
        guard duringActiveJob else { return }
        manager.stopMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
    }

    // MARK: - Validation

    /// Distance check: is `distance` within the on-site threshold?
    /// §57 spec: < 100 m for check-in validation.
    public static func isWithinCheckInRange(distanceMeters: CLLocationDistance) -> Bool {
        distanceMeters < 100
    }
}
