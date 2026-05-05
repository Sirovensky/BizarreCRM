import Foundation
import Observation

// MARK: - GeofencePolicy

/// Admin-configurable enforcement policy for geofence clock-in.
public enum GeofencePolicy: String, Sendable, CaseIterable {
    /// Location must be within the radius; clock-in is rejected otherwise.
    case strict
    /// Location is checked; a warning is shown but clock-in is allowed.
    case warn
    /// Geofence validation is disabled entirely.
    case off
}

// MARK: - GeofenceValidationResult

public enum GeofenceValidationResult: Sendable, Equatable {
    /// Within radius — proceed with clock-in.
    case withinRange(distance: Double)
    /// Outside radius — behavior depends on policy.
    case outsideRange(distance: Double, radius: Double)
    /// Location permission denied or unavailable.
    case locationUnavailable(reason: String)
    /// Policy is `off` — validation skipped.
    case skipped
    /// Employee opted out of location tracking.
    case optedOut
}

// MARK: - ShopCoordinate (platform-agnostic)

public struct ShopCoordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

// MARK: - GeofenceClockInValidator

/// Validates that the employee is within `radiusMeters` of the shop address
/// before allowing a clock-in.
///
/// Uses a one-shot `CLLocationManager` request on iOS/iPadOS.
/// On macOS (Swift Package test host) the implementation degrades to `.skipped`.
///
/// Privacy:
///  - `employeeOptedOut`: employee setting that skips all location checks.
///  - Policy `off`: admin setting that disables the feature globally.
///  - No location data is stored client-side; the coordinate is sent to the
///    server only on clock-in (if policy is strict/warn).
@MainActor
@Observable
public final class GeofenceClockInValidator {

    // MARK: - Configuration

    /// Shop location set by the tenant admin (fetched from Settings).
    public var shopCoordinate: ShopCoordinate? = nil
    /// Geofence radius in metres. Default: 100 m per spec.
    public var radiusMeters: Double = 100
    /// Admin policy.
    public var policy: GeofencePolicy = .strict
    /// Employee personal opt-out.
    public var employeeOptedOut: Bool = false

    // MARK: - State

    public private(set) var lastResult: GeofenceValidationResult = .skipped

    // MARK: - Init

    public init() {}

    // MARK: - Public

    /// Performs a one-shot location check and returns the validation result.
    ///
    /// Call before `ClockInOutViewModel.clockIn(pin:)`.
    public func validate() async -> GeofenceValidationResult {
        if policy == .off {
            lastResult = .skipped
            return .skipped
        }
        if employeeOptedOut {
            lastResult = .optedOut
            return .optedOut
        }
        guard let shop = shopCoordinate else {
            lastResult = .skipped
            return .skipped
        }

        let coordOpt = await GeofenceLocationService.requestOneShotCoordinate()
        guard let coord = coordOpt else {
            let result = GeofenceValidationResult.locationUnavailable(reason: "Could not determine location")
            lastResult = result
            return result
        }

        let distance = Self.haversineDistance(
            lat1: coord.latitude, lon1: coord.longitude,
            lat2: shop.latitude, lon2: shop.longitude
        )
        let result: GeofenceValidationResult = distance <= radiusMeters
            ? .withinRange(distance: distance)
            : .outsideRange(distance: distance, radius: radiusMeters)
        lastResult = result
        return result
    }

    // MARK: - Haversine (no CoreLocation dependency on macOS)

    /// Approximate distance in metres between two lat/lon points.
    public static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let r = 6_371_000.0 // earth radius metres
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

// MARK: - GeofenceLocationService

/// Thin wrapper that bridges CLLocationManager to async/await.
/// On macOS always returns `nil` (no CLLocationManager).
enum GeofenceLocationService {
    static func requestOneShotCoordinate() async -> ShopCoordinate? {
        #if canImport(UIKit)
        return await GeofenceLocationDelegate.shared.requestOneShot()
        #else
        return nil
        #endif
    }
}

// MARK: - GeofenceLocationDelegate (iOS/iPadOS only)

#if canImport(UIKit)
import CoreLocation

/// Delegate that wraps `CLLocationManager` one-shot request into async/await.
final class GeofenceLocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    static let shared = GeofenceLocationDelegate()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<ShopCoordinate?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func requestOneShot() async -> ShopCoordinate? {
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                cont.resume(returning: nil)
                self.continuation = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = ShopCoordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
        continuation?.resume(returning: coord)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            break // Await user decision
        default:
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
#endif
