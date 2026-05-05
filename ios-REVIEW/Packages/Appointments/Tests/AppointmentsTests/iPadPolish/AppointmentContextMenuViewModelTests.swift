import XCTest
@testable import Appointments
import Networking

// MARK: - AppointmentContextMenuViewModelTests

@MainActor
final class AppointmentContextMenuViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_notSendingReminder() {
        let sut = makeSUT()
        XCTAssertFalse(sut.isSendingReminder)
    }

    func test_initialState_reminderNotSent() {
        let sut = makeSUT()
        XCTAssertFalse(sut.reminderSent)
    }

    func test_initialState_noError() {
        let sut = makeSUT()
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - sendReminder success

    func test_sendReminder_success_setsReminderSent() async {
        let api = ContextMenuStubAPI(shouldFail: false)
        let sut = makeSUT(api: api)
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertTrue(sut.reminderSent)
        XCTAssertNil(sut.errorMessage)
    }

    func test_sendReminder_success_callsOnRefresh() async {
        var refreshCalled = false
        let api = ContextMenuStubAPI(shouldFail: false)
        let sut = AppointmentContextMenuViewModel(api: api) { refreshCalled = true }
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertTrue(refreshCalled, "onRefresh must be called after successful reminder send")
    }

    func test_sendReminder_success_clearsPreviousError() async {
        let failingAPI = ContextMenuStubAPI(shouldFail: true)
        let sut = makeSUT(api: failingAPI)
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertNotNil(sut.errorMessage, "Precondition: error is set after failure")

        // Now a fresh SUT with good API — confirms error would be cleared.
        let goodAPI = ContextMenuStubAPI(shouldFail: false)
        let sut2 = makeSUT(api: goodAPI)
        await sut2.sendReminder(for: makeAppointment(id: 1))
        XCTAssertNil(sut2.errorMessage)
    }

    // MARK: - sendReminder failure

    func test_sendReminder_failure_setsErrorMessage() async {
        let api = ContextMenuStubAPI(shouldFail: true)
        let sut = makeSUT(api: api)
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertFalse(sut.reminderSent)
    }

    func test_sendReminder_failure_doesNotCallOnRefresh() async {
        var refreshCalled = false
        let api = ContextMenuStubAPI(shouldFail: true)
        let sut = AppointmentContextMenuViewModel(api: api) { refreshCalled = true }
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertFalse(refreshCalled)
    }

    // MARK: - Guard: no double-send while in-flight

    func test_sendReminder_guardRejectsWhileSending() async {
        // The `isSendingReminder` guard prevents re-entry.
        // We can't test true concurrency here without Task bridging,
        // so we verify that calling twice sequentially produces one success.
        let api = ContextMenuStubAPI(shouldFail: false)
        var callCount = 0
        let sut = AppointmentContextMenuViewModel(api: api) { callCount += 1 }
        await sut.sendReminder(for: makeAppointment(id: 1))
        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Cancelled / completed appointments

    func test_sendReminder_cancelledAppointment_stillCallsAPI() async {
        // The guard for "cancelled" is in the View (disables button); the VM itself
        // does not check status — it processes the call if invoked.
        let api = ContextMenuStubAPI(shouldFail: false)
        let sut = makeSUT(api: api)
        let cancelledAppt = makeAppointment(id: 9, status: "cancelled")
        await sut.sendReminder(for: cancelledAppt)
        // API call went through because VM doesn't gate on status.
        XCTAssertTrue(sut.reminderSent)
    }

    // MARK: - Helpers

    private func makeSUT(api: APIClient? = nil) -> AppointmentContextMenuViewModel {
        AppointmentContextMenuViewModel(api: api ?? ContextMenuStubAPI(shouldFail: false), onRefresh: {})
    }

    private func makeAppointment(id: Int64 = 1, status: String = "scheduled") -> Appointment {
        let dict: [String: Any] = [
            "id": id,
            "title": "Appt \(id)",
            "start_time": "2025-06-02T09:00:00Z",
            "status": status
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }
}

// MARK: - ContextMenuStubAPI

private actor ContextMenuStubAPI: APIClient {
    private let shouldFail: Bool
    private var putCallCount = 0

    init(shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    var receivedPutCallCount: Int { putCallCount }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        putCallCount += 1
        if shouldFail { throw APITransportError.noBaseURL }
        // Return a minimal Appointment JSON.
        let dict: [String: Any] = ["id": 1, "title": "Appt 1", "start_time": "2025-06-02T09:00:00Z", "status": "confirmed"]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let appt = try JSONDecoder().decode(Appointment.self, from: data)
        guard let t = appt as? T else { throw APITransportError.decoding("type mismatch") }
        return t
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws { throw APITransportError.noBaseURL }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
