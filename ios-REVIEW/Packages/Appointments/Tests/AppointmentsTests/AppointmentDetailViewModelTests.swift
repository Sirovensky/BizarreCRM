import XCTest
@testable import Appointments
import Networking
import Core

// MARK: - AppointmentDetailViewModelTests

@MainActor
final class AppointmentDetailViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAppointment(
        id: Int64 = 1,
        title: String = "Pickup",
        status: String = "scheduled"
    ) -> Appointment {
        let dict: [String: Any] = ["id": id, "title": title, "status": status]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private func updatedAppt(status: String) -> Appointment {
        let dict: [String: Any] = ["id": 1, "title": "Pickup", "status": status]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private func makeSUT(
        updateResult: Result<Appointment, Error>
    ) -> (AppointmentDetailViewModel, DetailStubAPIClient) {
        let appt = makeAppointment()
        let api = DetailStubAPIClient(updateResult: updateResult)
        let vm = AppointmentDetailViewModel(appointment: appt, api: api)
        return (vm, api)
    }

    // MARK: - Initial state

    func test_initialState_appointmentSet() {
        let (vm, _) = makeSUT(updateResult: .success(updatedAppt(status: "completed")))
        XCTAssertEqual(vm.appointment.title, "Pickup")
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.markedNoShow)
        XCTAssertFalse(vm.markedCompleted)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Mark no-show

    func test_markNoShow_success_setsMarkedNoShow() async {
        let (vm, _) = makeSUT(updateResult: .success(updatedAppt(status: "no-show")))
        await vm.markNoShow()
        XCTAssertTrue(vm.markedNoShow)
        XCTAssertNil(vm.errorMessage)
    }

    func test_markNoShow_updatesAppointmentStatus() async {
        let (vm, _) = makeSUT(updateResult: .success(updatedAppt(status: "no-show")))
        await vm.markNoShow()
        XCTAssertEqual(vm.appointment.status, "no-show")
    }

    func test_markNoShow_apiError_setsErrorMessage() async {
        let (vm, _) = makeSUT(
            updateResult: .failure(APITransportError.httpStatus(404, message: nil))
        )
        await vm.markNoShow()
        XCTAssertFalse(vm.markedNoShow)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Mark completed

    func test_markCompleted_success_setsMarkedCompleted() async {
        let (vm, _) = makeSUT(updateResult: .success(updatedAppt(status: "completed")))
        await vm.markCompleted()
        XCTAssertTrue(vm.markedCompleted)
        XCTAssertNil(vm.errorMessage)
    }

    func test_markCompleted_updatesAppointmentStatus() async {
        let (vm, _) = makeSUT(updateResult: .success(updatedAppt(status: "completed")))
        await vm.markCompleted()
        XCTAssertEqual(vm.appointment.status, "completed")
    }

    func test_markCompleted_apiError_setsErrorMessage() async {
        let (vm, _) = makeSUT(
            updateResult: .failure(APITransportError.httpStatus(403, message: nil))
        )
        await vm.markCompleted()
        XCTAssertFalse(vm.markedCompleted)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Idempotency

    func test_markNoShow_duringLoading_ignoresSecondCall() async {
        let (vm, api) = makeSUT(updateResult: .success(updatedAppt(status: "no-show")))
        async let first: () = vm.markNoShow()
        async let second: () = vm.markNoShow()
        _ = await (first, second)
        XCTAssertLessThanOrEqual(api.putCallCount, 1)
    }

    // MARK: - §10.2 Appointment model field helpers

    func test_typeDisplayName_hyphenated_capitalizes() {
        let dict: [String: Any] = ["id": 1, "appointment_type": "on-site"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertEqual(appt.typeDisplayName, "On Site")
    }

    func test_typeDisplayName_nilWhenMissing() {
        let dict: [String: Any] = ["id": 1]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertNil(appt.typeDisplayName)
    }

    func test_typeDisplayName_dropOff_capitalizes() {
        let dict: [String: Any] = ["id": 1, "appointment_type": "drop-off"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertEqual(appt.typeDisplayName, "Drop Off")
    }

    func test_customerPhone_decodesFromModel() {
        let dict: [String: Any] = ["id": 1, "customer_phone": "+15551234567"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertEqual(appt.customerPhone, "+15551234567")
    }

    func test_customerEmail_decodesFromModel() {
        let dict: [String: Any] = ["id": 1, "customer_email": "test@example.com"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertEqual(appt.customerEmail, "test@example.com")
    }

    func test_locationId_decodesFromModel() {
        let dict: [String: Any] = ["id": 1, "location_id": 3]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let appt = try! JSONDecoder().decode(Appointment.self, from: data)
        XCTAssertEqual(appt.locationId, 3)
    }
}

// MARK: - DetailStubAPIClient

private actor DetailStubAPIClient: APIClient {
    let updateResult: Result<Appointment, Error>
    private(set) var putCallCount: Int = 0

    init(updateResult: Result<Appointment, Error>) {
        self.updateResult = updateResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        putCallCount += 1
        switch updateResult {
        case .success(let r):
            guard let t = r as? T else { throw APITransportError.decoding("type") }
            return t
        case .failure(let e):
            throw e
        }
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
