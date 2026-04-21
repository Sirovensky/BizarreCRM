// Tests for FieldCheckInService.
// Coverage target: ≥80% of FieldCheckInService.
//
// Design: FieldCheckInService is an actor. Tests go through the public API
// with mock LocationCapture and MockAPIClient. Geocoding is not live-tested
// (network) — the proximity check is tested via FieldLocationPolicy unit tests.

import XCTest
import CoreLocation
@testable import FieldService

final class FieldCheckInServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        locationError: Error? = nil,
        postError: Error? = nil
    ) -> (FieldCheckInService, MockAPIClient, MockLocationCapture) {
        let api = MockAPIClient()
        api.postShouldThrow = postError
        let capture = MockLocationCapture()
        capture.stubbedError = locationError
        if locationError == nil {
            capture.stubbedLocation = CLLocation(latitude: 37.3347, longitude: -122.0090)
        }
        let sut = FieldCheckInService(api: api, locationCapture: capture)
        return (sut, api, capture)
    }

    // MARK: - checkIn error paths

    func test_checkIn_locationTimeout_throws() async {
        let (sut, _, _) = makeService(locationError: FieldCheckInError.locationTimeout)
        do {
            try await sut.checkIn(appointmentId: 1, customerAddress: "irrelevant")
            XCTFail("Expected FieldCheckInError.locationTimeout")
        } catch FieldCheckInError.locationTimeout {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_checkIn_permissionDenied_throws() async {
        let (sut, _, _) = makeService(locationError: FieldCheckInError.locationPermissionDenied)
        do {
            try await sut.checkIn(appointmentId: 2, customerAddress: "irrelevant")
            XCTFail("Expected FieldCheckInError.locationPermissionDenied")
        } catch FieldCheckInError.locationPermissionDenied {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - checkOut

    func test_checkOut_success() async throws {
        let (sut, _, _) = makeService()
        let sig = Data("signature".utf8)
        // Should not throw — MockAPIClient.post returns {} for any request.
        try await sut.checkOut(appointmentId: 10, signature: sig)
    }

    func test_checkOut_networkFailure_throwsNetworkError() async {
        let (sut, _, _) = makeService(postError: MockError.simulated)
        let sig = Data("signature".utf8)
        do {
            try await sut.checkOut(appointmentId: 11, signature: sig)
            XCTFail("Expected networkError")
        } catch FieldCheckInError.networkError {
            // pass
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
