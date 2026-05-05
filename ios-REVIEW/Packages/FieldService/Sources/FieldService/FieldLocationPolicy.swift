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

    // MARK: - Indoor fallback

    /// §57 Indoor fallback source — describes which positioning technology
    /// a `CLLocation` was derived from so callers can degrade gracefully.
    public enum PositioningSource: Sendable {
        /// GPS fix with accuracy ≤ indoorGPSThreshold (20 m).
        case gps
        /// Cell-tower / Wi-Fi derived position (horizontalAccuracy > 20 m but
        /// `CLLocation` has no dedicated property; inferred from accuracy bucket).
        case cellAndWifi
        /// No fix available — caller should show "Location unavailable" instead
        /// of silently failing.
        case unavailable
    }

    /// §57 Indoor GPS threshold: accuracy > 20 m signals weak / indoor GPS.
    public static let indoorGPSThresholdMeters: CLLocationAccuracy = 20

    /// Classify the positioning source from a `CLLocation`.
    ///
    /// CoreLocation doesn't expose the physical radio used, but horizontal-
    /// accuracy buckets are reliable proxies:
    /// - ≤ 20 m  → GPS lock (outdoor / clear sky)
    /// - 21–200 m → cell-tower + Wi-Fi assisted (typical indoors)
    /// - > 200 m or negative → unavailable / invalid
    ///
    /// Callers should call `isWithinCheckInRange` only when the source is
    /// `.gps`; for `.cellAndWifi` they should show a banner "Using approximate
    /// location" and still allow manual check-in override.
    public static func positioningSource(from location: CLLocation) -> PositioningSource {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0 else { return .unavailable }
        if accuracy <= indoorGPSThresholdMeters { return .gps }
        if accuracy <= 200 { return .cellAndWifi }
        return .unavailable
    }

    /// Whether a location fix is good enough for on-site check-in.
    ///
    /// Returns `true` for GPS fixes within the 100 m range.
    /// Returns `false` for cell/Wi-Fi (accuracy > 20 m) so the caller can
    /// fall back to a manual check-in confirmation sheet instead of hard-
    /// failing the check-in.
    public static func canAutoCheckIn(location: CLLocation, jobCoordinate: CLLocationCoordinate2D) -> Bool {
        guard positioningSource(from: location) == .gps else { return false }
        let jobLocation = CLLocation(latitude: jobCoordinate.latitude, longitude: jobCoordinate.longitude)
        return isWithinCheckInRange(distanceMeters: location.distance(from: jobLocation))
    }

    /// Banner copy for degraded positioning. Returns `nil` when GPS is fine.
    public static func indoorBannerMessage(source: PositioningSource) -> String? {
        switch source {
        case .gps:         return nil
        case .cellAndWifi: return "Using approximate location (indoors). Check-in manually if needed."
        case .unavailable: return "Location unavailable. Check-in manually."
        }
    }
}
