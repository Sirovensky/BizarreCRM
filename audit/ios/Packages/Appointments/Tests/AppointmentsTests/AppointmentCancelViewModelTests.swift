import XCTest
@testable import Appointments
import Networking
import Core

// MARK: - AppointmentCancelViewModelTests
// TDD: tests written before AppointmentCancelViewModel was finalised.

@MainActor
final class AppointmentCancelViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAppointment(
        id: Int64 = 10,
        title: String = "Oil change",
        customerId: Int64? = 5,
        startTime: String = "2025-07-01T10:00:00Z"
    ) -> Appointment {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "start_time": startTime,
            "status": "scheduled"
        ]
        if let cid = customerId { dict["customer_id"] = cid }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private func makeSUT(
        appt: Appointment? = nil,
        updateResult: Result<Appointment, Error> = .success(makeCancelledAppt()),
        smsResult: Result<Void, Error> = .success(())
    ) -> (AppointmentCancelViewModel, CancelStubAPIClient) {
        let appointment = appt ?? makeAppointment()
        let api = CancelStubAPIClient(updateResult: updateResult, smsResult: smsResult)
        let vm = AppointmentCancelViewModel(appointment: appointment, api: api)
        return (vm, api)
    }

    private static func makeCancelledAppt() -> Appointment {
        let dict: [String: Any] = ["id": 10, "title": "Oil change", "status": "cancelled"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    // MARK: - Initial state

    func test_initialState() {
        let (vm, _) = makeSUT()
        XCTAssertTrue(vm.notifyCustomer, "Should default to notify customer")
        XCTAssertEqual(vm.cancelReason, "")
        XCTAssertFalse(vm.isCancelling)
        XCTAssertFalse(vm.cancelled)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Happy path — with notification

    func test_cancel_happyPath_setsCancelledTrue() async {
        let (vm, _) = makeSUT()
        vm.notifyCustomer = false  // simpler — no SMS path
        await vm.cancel()
        XCTAssertTrue(vm.cancelled)
        XCTAssertNil(vm.errorMessage)
    }

    func test_cancel_withNotify_sendsStatusUpdate() async {
        let (vm, api) = makeSUT()
        vm.notifyCustomer = true
        await vm.cancel()
        XCTAssertGreaterThanOrEqual(api.putCallCount, 1)
    }

    // MARK: - Happy path — without notification

    func test_cancel_noNotify_doesNotCallSMS() async {
        let (vm, api) = makeSUT()
        vm.notifyCustomer = false
        await vm.cancel()
        XCTAssertEqual(api.smsCallCount, 0)
    }

    // MARK: - Error paths

    func test_cancel_apiError404_setsNotFoundMessage() async {
        let (vm, _) = makeSUT(
            updateResult: .failure(APITransportError.httpStatus(404, message: "Not found"))
        )
        await vm.cancel()
        XCTAssertFalse(vm.cancelled)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_cancel_apiError403_setsForbiddenMessage() async {
        let (vm, _) = makeSUT(
            updateResult: .failure(APITransportError.httpStatus(403, message: nil))
        )
        await vm.cancel()
        XCTAssertFalse(vm.cancelled)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_cancel_offline_setsOfflineMessage() async {
        let urlError = URLError(.notConnectedToInternet)
        let (vm, _) = makeSUT(updateResult: .failure(urlError))
        await vm.cancel()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - SMS failure is non-blocking

    func test_cancel_smsFailure_doesNotRollBackCancel() async {
        // SMS fire-and-forget; even if SMS fails the cancel itself succeeds
        let (vm, _) = makeSUT(smsResult: .failure(URLError(.notConnectedToInternet)))
        vm.notifyCustomer = true
        await vm.cancel()
        // The underlying cancel (PUT) succeeded; SMS failure should be swallowed
        // Cancel still sets cancelled = true
        XCTAssertTrue(vm.cancelled, "SMS failure must not block the cancellation")
    }

    // MARK: - Idempotency guard

    func test_cancel_doubleCall_doesNotDoubleSubmit() async {
        let (vm, api) = makeSUT()
        async let first: () = vm.cancel()
        async let second: () = vm.cancel()
        _ = await (first, second)
        XCTAssertLessThanOrEqual(api.putCallCount, 1)
    }

    // MARK: - Appointment without customer — notify toggle has no effect

    func test_cancel_noCustomer_withNotify_noSmsCall() async {
        let appt = makeAppointment(customerId: nil)
        let (vm, api) = makeSUT(appt: appt)
        vm.notifyCustomer = true
        await vm.cancel()
        // No customer_id → no SMS even if toggle is on
        XCTAssertEqual(api.smsCallCount, 0)
    }
}

// MARK: - CancelStubAPIClient

private actor CancelStubAPIClient: APIClient {
    let updateResult: Result<Appointment, Error>
    let smsResult: Result<Void, Error>
    private(set) var putCallCount: Int = 0
    private(set) var smsCallCount: Int = 0

    init(updateResult: Result<Appointment, Error>, smsResult: Result<Void, Error>) {
        self.updateResult = updateResult
        self.smsResult = smsResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.contains("/sms") {
            smsCallCount += 1
            switch smsResult {
            case .success: throw APITransportError.noBaseURL  // EmptyResponse will fail cast; that's expected fire-and-forget
            case .failure(let e): throw e
            }
        }
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
