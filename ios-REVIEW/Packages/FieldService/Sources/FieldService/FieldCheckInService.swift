// §57.2 FieldCheckInService — GPS-verified arrival + signature checkout.
//
// LOCATION ENTITLEMENT NOTE:
// `requestAlwaysAuthorization` (used by FieldLocationPolicy for field-role
// step-up) requires `com.apple.developer.location.push` entitlement and
// NSLocationAlwaysAndWhenInUseUsageDescription in Info.plist.
// Add the key via scripts/write-info-plist.sh. DO NOT touch entitlements
// directly — file ownership per ios/CLAUDE.md.
//
// This actor only requests whenInUse (one-shot capture); no background
// entitlement required for check-in/out flows.

import Foundation
import CoreLocation
import Networking
import Core

// MARK: - LocationCapture protocol (injectable for tests)

public protocol LocationCapture: Sendable {
    /// Capture one location fix. Resolves or throws.
    func captureCurrentLocation() async throws -> CLLocation
}

// MARK: - CheckInRequest / CheckOutRequest

struct CheckInBody: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
}

struct CheckOutBody: Encodable, Sendable {
    let signatureBase64: String
}

// MARK: - FieldCheckInError

public enum FieldCheckInError: Error, LocalizedError, Sendable {
    case locationPermissionDenied
    case locationTimeout
    case tooFarFromSite(distanceMeters: Double)
    case geocodingFailed
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .locationPermissionDenied:
            return "Location access is required for check-in. Please enable it in Settings."
        case .locationTimeout:
            return "Could not determine your location. Please try again."
        case .tooFarFromSite(let d):
            return String(format: "You are %.0f m from the job site (max 100 m).", d)
        case .geocodingFailed:
            return "Could not resolve the customer address. Check-in requires a valid address."
        case .networkError(let msg):
            return "Check-in failed: \(msg)"
        }
    }
}

// MARK: - FieldCheckInServiceProtocol

/// Protocol for testability — `FieldCheckInPromptViewModel` depends on this.
public protocol FieldCheckInServiceProtocol: Actor {
    func checkIn(appointmentId: Int64, customerAddress: String) async throws
    func checkOut(appointmentId: Int64, signature: Data) async throws
}

// MARK: - FieldCheckInService

/// §57.2 — Actor that handles GPS-verified check-in and signature check-out.
///
/// Dependency on `LocationCapture` means tests can inject a mock without
/// requiring a real CLLocationManager or host app.
public actor FieldCheckInService: FieldCheckInServiceProtocol {

    // MARK: - Dependencies

    let api: APIClient
    let locationCapture: LocationCapture
    private let geocoder: CLGeocoder

    // MARK: - Init

    public init(api: APIClient, locationCapture: LocationCapture) {
        self.api = api
        self.locationCapture = locationCapture
        self.geocoder = CLGeocoder()
    }

    // MARK: - Check-in

    /// Captures a one-shot GPS fix, validates the technician is within 100 m
    /// of the customer address, then POSTs to `/appointments/:id/check-in`.
    ///
    /// - Parameters:
    ///   - appointmentId: The appointment to check in to.
    ///   - customerAddress: Full address string used for geocoding proximity.
    public func checkIn(appointmentId: Int64, customerAddress: String) async throws {
        // 1. Capture current location.
        let location: CLLocation
        do {
            location = try await locationCapture.captureCurrentLocation()
        } catch is CancellationError {
            throw FieldCheckInError.locationTimeout
        }

        // 2. Geocode customer address to CLLocation.
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.geocodeAddressString(customerAddress)
        } catch {
            AppLog.ui.error("FieldCheckIn geocoding failed: \(error.localizedDescription, privacy: .public)")
            throw FieldCheckInError.geocodingFailed
        }

        guard let siteLocation = placemarks.first?.location else {
            throw FieldCheckInError.geocodingFailed
        }

        // 3. Validate proximity (< 100 m per §57 spec).
        let distance = location.distance(from: siteLocation)
        guard FieldLocationPolicy.isWithinCheckInRange(distanceMeters: distance) else {
            throw FieldCheckInError.tooFarFromSite(distanceMeters: distance)
        }

        // 4. POST check-in with lat/long.
        let body = CheckInBody(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy
        )
        do {
            _ = try await api.post(
                "/appointments/\(appointmentId)/check-in",
                body: body,
                as: EmptyResponse.self
            )
        } catch {
            AppLog.ui.error("FieldCheckIn POST failed: \(error.localizedDescription, privacy: .public)")
            throw FieldCheckInError.networkError(error.localizedDescription)
        }

        AppLog.ui.info("FieldCheckIn: checked in to appointment \(appointmentId, privacy: .public)")
    }

    // MARK: - Check-out

    /// POSTs the customer signature PNG to `/appointments/:id/check-out`.
    ///
    /// - Parameters:
    ///   - appointmentId: The appointment to check out of.
    ///   - signature: PNG data from `FieldSignatureView`.
    public func checkOut(appointmentId: Int64, signature: Data) async throws {
        let base64 = signature.base64EncodedString()
        let body = CheckOutBody(signatureBase64: base64)
        do {
            _ = try await api.post(
                "/appointments/\(appointmentId)/check-out",
                body: body,
                as: EmptyResponse.self
            )
        } catch {
            AppLog.ui.error("FieldCheckOut POST failed: \(error.localizedDescription, privacy: .public)")
            throw FieldCheckInError.networkError(error.localizedDescription)
        }

        AppLog.ui.info("FieldCheckIn: checked out of appointment \(appointmentId, privacy: .public)")
    }
}

// MARK: - EmptyResponse helper

private struct EmptyResponse: Decodable, Sendable {}
