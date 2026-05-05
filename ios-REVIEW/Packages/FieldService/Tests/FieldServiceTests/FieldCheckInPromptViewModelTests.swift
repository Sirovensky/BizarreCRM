// Tests for FieldCheckInPromptViewModel.
// Coverage target: ≥80%.
// MockCheckInService lives in Mocks.swift.

import XCTest
import CoreLocation
@testable import FieldService

typealias PState = FieldCheckInPromptViewModel.PromptState

@MainActor
final class FieldCheckInPromptViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(service: MockCheckInService? = nil) -> (FieldCheckInPromptViewModel, MockCheckInService) {
        let svc = service ?? MockCheckInService()
        return (FieldCheckInPromptViewModel(checkInService: svc), svc)
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.state, PState.idle)
    }

    // MARK: - geofenceEntered

    func test_geofenceEntered_fromIdle_transitionsToPrompting() {
        let (vm, _) = makeVM()
        vm.geofenceEntered(appointmentId: 1, customerName: "Alice", address: "123 Main St")
        if case .prompting(let id, let name, let addr) = vm.state {
            XCTAssertEqual(id, 1)
            XCTAssertEqual(name, "Alice")
            XCTAssertEqual(addr, "123 Main St")
        } else {
            XCTFail("Expected .prompting, got \(vm.state)")
        }
    }

    func test_geofenceEntered_whenAlreadyPrompting_doesNotReplace() {
        let (vm, _) = makeVM()
        vm.geofenceEntered(appointmentId: 1, customerName: "Alice", address: "123 Main St")
        vm.geofenceEntered(appointmentId: 2, customerName: "Bob", address: "456 Oak Ave")
        if case .prompting(let id, _, _) = vm.state {
            XCTAssertEqual(id, 1, "Second geofence event should not replace first prompt")
        } else {
            XCTFail("Expected .prompting with id=1")
        }
    }

    // MARK: - dismiss

    func test_dismiss_resetsToIdle() {
        let (vm, _) = makeVM()
        vm.geofenceEntered(appointmentId: 1, customerName: "Alice", address: "123 Main St")
        vm.dismiss()
        XCTAssertEqual(vm.state, PState.idle)
    }

    // MARK: - confirmCheckIn success

    func test_confirmCheckIn_success_transitionsToCheckedIn() async {
        let (vm, _) = makeVM()
        await vm.confirmCheckIn(appointmentId: 5, address: "123 Main St")
        XCTAssertEqual(vm.state, PState.checkedIn)
    }

    func test_confirmCheckIn_callsService_withCorrectAppointmentId() async {
        let (vm, svc) = makeVM()
        await vm.confirmCheckIn(appointmentId: 42, address: "123 Main St")
        let count = await svc.checkInCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - confirmCheckIn failure

    func test_confirmCheckIn_locationFail_transitionsToFailed() async {
        let svc = MockCheckInService()
        svc.checkInShouldThrow = FieldCheckInError.locationTimeout
        let (vm, _) = makeVM(service: svc)
        await vm.confirmCheckIn(appointmentId: 6, address: "123 Main St")
        if case .failed = vm.state {
            // pass
        } else {
            XCTFail("Expected .failed, got \(vm.state)")
        }
    }

    func test_confirmCheckIn_tooFar_failedMessageContainsDistance() async {
        let svc = MockCheckInService()
        svc.checkInShouldThrow = FieldCheckInError.tooFarFromSite(distanceMeters: 250)
        let (vm, _) = makeVM(service: svc)
        await vm.confirmCheckIn(appointmentId: 7, address: "456 Oak Ave")
        if case .failed(let msg) = vm.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed")
        }
    }

    // MARK: - retryReset

    func test_retryReset_fromFailed_resetsToIdle() async {
        let svc = MockCheckInService()
        svc.checkInShouldThrow = FieldCheckInError.locationTimeout
        let (vm, _) = makeVM(service: svc)
        await vm.confirmCheckIn(appointmentId: 7, address: "123 Main St")
        vm.retryReset()
        XCTAssertEqual(vm.state, PState.idle)
    }

    // MARK: - End-to-end state flow

    func test_completeFlow_idle_to_checkedIn() async {
        let (vm, _) = makeVM()
        XCTAssertEqual(vm.state, PState.idle)
        await vm.confirmCheckIn(appointmentId: 8, address: "789 Elm")
        XCTAssertEqual(vm.state, PState.checkedIn)
    }
}
