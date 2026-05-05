// §57.1 FieldServiceRouteService — MapKit routing to the next appointment.
//
// Calls MKDirections.calculate for ETA display and opens Apple Maps for
// turn-by-turn navigation. No third-party SDK — MapKit only.

import Foundation
@preconcurrency import MapKit
import CoreLocation

// MARK: - RouteResult

public struct RouteResult: @unchecked Sendable {
    public let expectedTravelTime: TimeInterval
    public let distanceMeters: CLLocationDistance
    public let polyline: MKPolyline

    public var etaMinutes: Int {
        Int(ceil(expectedTravelTime / 60))
    }
}

// MARK: - FieldServiceRouteService

public actor FieldServiceRouteService {

    // MARK: - Init

    public init() {}

    // MARK: - Calculate route

    /// Calculates the driving route from `origin` to `destination`.
    /// Uses `MKDirections.calculate` — wraps the callback in async/await.
    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> RouteResult {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            throw FieldRouteError.noRouteFound
        }

        return RouteResult(
            expectedTravelTime: route.expectedTravelTime,
            distanceMeters: route.distance,
            polyline: route.polyline
        )
    }

    // MARK: - Open Apple Maps

    /// Opens Apple Maps with turn-by-turn directions to `coordinate`.
    @MainActor
    public static func openInMaps(
        coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}

// MARK: - FieldRouteError

public enum FieldRouteError: Error, LocalizedError, Sendable {
    case noRouteFound

    public var errorDescription: String? {
        "No driving route could be found to the job site."
    }
}
