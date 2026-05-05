// Tests for JobDetailViewModel — §57.2
// Coverage target: ≥80% of JobDetailViewModel.
//
// Tests cover: load, status update (with and without location),
// location-denied fallback, and error states.

import XCTest
import CoreLocation
@testable import FieldService

@MainActor
final class JobDetailViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        job: FSJob = .makeTest(),
        detailError: Error? = nil,
        statusError: Error? = nil,
        locationError: Error? = nil,
        locationResult: CLLocation? = CLLocation(latitude: 37.33, longitude: -122.02)
    ) -> (JobDetailViewModel, MockAPIClient, MockLocationCapture) {
        let api = MockAPIClient()
        api.stubbedJobs = [job]
        api.fsDetailShouldThrow = detailError
        api.fsStatusShouldThrow = statusError

        let capture = MockLocationCapture()
        if let err = locationError {
            capture.stubbedError = err
        } else {
            capture.stubbedLocation = locationResult
        }

        let vm = JobDetailViewModel(jobId: job.id, api: api, locationCapture: capture)
        return (vm, api, capture)
    }

    // MARK: - load()

    func test_load_success_transitionsToLoaded() async {
        let job = FSJob.makeTest(id: 7, status: .assigned)
        let (vm, _, _) = makeVM(job: job)

        await vm.load()

        if case .loaded(let loaded) = vm.state {
            XCTAssertEqual(loaded.id, 7)
            XCTAssertEqual(loaded.status, FSJobStatus.assigned.rawValue)
        } else {
            XCTFail("Expected .loaded, got \(vm.state)")
        }
    }

    func test_load_networkError_transitionsToFailed() async {
        let (vm, _, _) = makeVM(detailError: MockError.simulated)

        await vm.load()

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_load_initialState_isLoading() {
        let (vm, _, _) = makeVM()
        XCTAssertEqual(vm.state, .loading)
    }

    // MARK: - retry()

    func test_retry_afterError_reloads() async {
        let (vm, api, _) = makeVM(detailError: MockError.simulated)
        await vm.load()

        if case .failed = vm.state {
            // good — now clear error and retry
        } else {
            XCTFail("Expected .failed after first load")
        }

        api.fsDetailShouldThrow = nil
        await vm.retry()

        if case .loaded = vm.state {
            // pass
        } else {
            XCTFail("Expected .loaded after retry, got \(vm.state)")
        }
    }

    // MARK: - updateStatus() — happy path, no location

    func test_updateStatus_noLocationCapture_sendsStatusWithoutCoords() async {
        let job = FSJob.makeTest(id: 3, status: .assigned)
        let api = MockAPIClient()
        api.stubbedJobs = [job]
        let vm = JobDetailViewModel(jobId: 3, api: api, locationCapture: nil)

        await vm.load()
        await vm.updateStatus(to: .enRoute)

        XCTAssertNotNil(api.lastStatusRequest)
        XCTAssertEqual(api.lastStatusRequest?.status, FSJobStatus.enRoute.rawValue)
        XCTAssertNil(api.lastStatusRequest?.locationLat)
        XCTAssertNil(api.lastStatusRequest?.locationLng)

        if case .updated(_, let newStatus) = vm.state {
            XCTAssertEqual(newStatus, .enRoute)
        } else {
            XCTFail("Expected .updated, got \(vm.state)")
        }
    }

    // MARK: - updateStatus() — on_site with location

    func test_updateStatus_onSite_sendsLocationCoords() async {
        let job = FSJob.makeTest(id: 4, status: .enRoute)
        let loc = CLLocation(latitude: 37.3347, longitude: -122.0090)
        let (vm, api, _) = makeVM(job: job, locationResult: loc)

        await vm.load()
        await vm.updateStatus(to: .onSite)

        XCTAssertEqual(api.lastStatusRequest?.status, FSJobStatus.onSite.rawValue)
        XCTAssertEqual(api.lastStatusRequest?.locationLat, loc.coordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(api.lastStatusRequest?.locationLng, loc.coordinate.longitude, accuracy: 0.0001)

        if case .updated(_, let newStatus) = vm.state {
            XCTAssertEqual(newStatus, .onSite)
        } else {
            XCTFail("Expected .updated, got \(vm.state)")
        }

        // No alert when location succeeds.
        XCTAssertNil(vm.alertMessage)
    }

    // MARK: - updateStatus() — location permission denied fallback

    func test_updateStatus_onSite_locationDenied_fallsBackToManual() async {
        let job = FSJob.makeTest(id: 5, status: .enRoute)
        let (vm, api, _) = makeVM(
            job: job,
            locationError: FieldCheckInError.locationPermissionDenied
        )

        await vm.load()
        await vm.updateStatus(to: .onSite)

        // Status should still be sent, but without coords.
        XCTAssertEqual(api.lastStatusRequest?.status, FSJobStatus.onSite.rawValue)
        XCTAssertNil(api.lastStatusRequest?.locationLat)
        XCTAssertNil(api.lastStatusRequest?.locationLng)

        // Alert message should be set.
        XCTAssertNotNil(vm.alertMessage)
        XCTAssertTrue(vm.alertMessage?.contains("denied") == true || vm.alertMessage?.contains("Location") == true)

        // State should be .updated.
        if case .updated = vm.state {
            // pass
        } else {
            XCTFail("Expected .updated even with location denied, got \(vm.state)")
        }
    }

    func test_updateStatus_locationUnavailable_fallsBackToManual() async {
        let job = FSJob.makeTest(id: 6, status: .enRoute)
        let (vm, api, _) = makeVM(
            job: job,
            locationError: FieldCheckInError.locationTimeout
        )

        await vm.load()
        await vm.updateStatus(to: .onSite)

        XCTAssertNil(api.lastStatusRequest?.locationLat)
        XCTAssertNotNil(vm.alertMessage)
    }

    // MARK: - updateStatus() — server error

    func test_updateStatus_serverError_transitionsToFailed() async {
        let job = FSJob.makeTest(id: 8, status: .assigned)
        let (vm, _, _) = makeVM(job: job, statusError: MockError.simulated)

        await vm.load()
        await vm.updateStatus(to: .enRoute)

        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed after server error, got \(vm.state)")
        }
    }

    // MARK: - updateStatus() — guard: must be loaded first

    func test_updateStatus_whenNotLoaded_isNoOp() async {
        let (vm, api, _) = makeVM()
        // Don't call load() — still in .loading

        await vm.updateStatus(to: .enRoute)

        XCTAssertNil(api.lastStatusRequest)
        XCTAssertEqual(vm.state, .loading)
    }

    // MARK: - dismissAlert()

    func test_dismissAlert_clearsAlertMessage() async {
        let job = FSJob.makeTest(id: 9, status: .enRoute)
        let (vm, _, _) = makeVM(
            job: job,
            locationError: FieldCheckInError.locationPermissionDenied
        )

        await vm.load()
        await vm.updateStatus(to: .onSite)
        XCTAssertNotNil(vm.alertMessage)

        vm.dismissAlert()
        XCTAssertNil(vm.alertMessage)
    }

    // MARK: - Notes

    func test_updateStatus_withNotes_passesNotesToRequest() async {
        let job = FSJob.makeTest(id: 10, status: .onSite)
        let api = MockAPIClient()
        api.stubbedJobs = [job]
        let vm = JobDetailViewModel(jobId: 10, api: api, locationCapture: nil)

        await vm.load()
        await vm.updateStatus(to: .completed, notes: "Fixed the issue.")

        XCTAssertEqual(api.lastStatusRequest?.notes, "Fixed the issue.")
    }
}
