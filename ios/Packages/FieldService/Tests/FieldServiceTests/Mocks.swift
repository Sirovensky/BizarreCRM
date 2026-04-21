// Test mocks for FieldService package tests.

import Foundation
import CoreLocation
import Networking
import Core
@testable import FieldService

// MARK: - MockAPIClient

final class MockAPIClient: APIClient, @unchecked Sendable {

    // MARK: - Configurable stubs

    var postShouldThrow: Error?
    var getShouldThrow: Error?

    // MARK: - APIClient conformance

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = getShouldThrow { throw err }
        throw MockError.notConfigured("GET \(path)")
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if let err = postShouldThrow { throw err }
        // Return a bare Decodable from empty JSON `{}`.
        let data = "{}".data(using: .utf8)!
        return try JSONDecoder().decode(T.self, from: data)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured("PUT \(path)")
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw MockError.notConfigured("PATCH \(path)")
    }

    func delete(_ path: String) async throws {
        throw MockError.notConfigured("DELETE \(path)")
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw MockError.notConfigured("getEnvelope \(path)")
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - MockLocationCapture

final class MockLocationCapture: LocationCapture, @unchecked Sendable {
    var stubbedLocation: CLLocation?
    var stubbedError: Error?

    func captureCurrentLocation() async throws -> CLLocation {
        if let err = stubbedError { throw err }
        if let loc = stubbedLocation { return loc }
        throw FieldCheckInError.locationTimeout
    }
}

// MARK: - MockCLLocationManager

final class MockCLLocationManager: CLLocationManagerProtocol, @unchecked Sendable {

    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var requestedWhenInUse = false
    private(set) var requestedAlways = false
    private(set) var startedUpdating = false
    private(set) var stoppedUpdating = false
    private(set) var startedSignificant = false
    private(set) var stoppedSignificant = false

    func requestWhenInUseAuthorization() { requestedWhenInUse = true }
    func requestAlwaysAuthorization() { requestedAlways = true }
    func startUpdatingLocation() { startedUpdating = true }
    func stopUpdatingLocation() { stoppedUpdating = true }
    func startMonitoringSignificantLocationChanges() { startedSignificant = true }
    func stopMonitoringSignificantLocationChanges() { stoppedSignificant = true }
}

// MARK: - MockCheckInService

actor MockCheckInService: FieldCheckInServiceProtocol {
    // nonisolated(unsafe) lets tests set these from @MainActor context.
    nonisolated(unsafe) var checkInShouldThrow: Error?
    nonisolated(unsafe) var checkOutShouldThrow: Error?
    private(set) var checkInCallCount = 0

    func checkIn(appointmentId: Int64, customerAddress: String) async throws {
        checkInCallCount += 1
        if let err = checkInShouldThrow { throw err }
    }

    func checkOut(appointmentId: Int64, signature: Data) async throws {
        if let err = checkOutShouldThrow { throw err }
    }
}

// MARK: - MockError

enum MockError: Error {
    case notConfigured(String)
    case simulated
}
