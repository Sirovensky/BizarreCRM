import XCTest
@testable import Appointments
import Networking

// MARK: - AppointmentsThreeColumnViewModelTests

@MainActor
final class AppointmentsThreeColumnViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isEmpty() {
        let sut = makeSUT()
        XCTAssertTrue(sut.allAppointments.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertEqual(sut.selectedScope, .today)
        XCTAssertNil(sut.selectedAppointment)
    }

    // MARK: - load

    func test_load_setsAppointments() async {
        let appts = [makeAppointment(id: 1, startTime: iso(Date()))]
        let api = ThreeColStubAPI(appointments: appts)
        let sut = makeSUT(api: api)
        await sut.load()
        XCTAssertEqual(sut.allAppointments.count, 1)
        XCTAssertNil(sut.errorMessage)
    }

    func test_load_onError_setsErrorMessage() async {
        let api = ThreeColStubAPI(error: APITransportError.noBaseURL)
        let sut = makeSUT(api: api)
        await sut.load()
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.allAppointments.isEmpty)
    }

    func test_load_clearsErrorOnRetry() async {
        let errorAPI = ThreeColStubAPI(error: APITransportError.noBaseURL)
        let sut = makeSUT(api: errorAPI)
        await sut.load()
        XCTAssertNotNil(sut.errorMessage)

        // Second call to a good API — error should clear.
        let goodAPI = ThreeColStubAPI(appointments: [makeAppointment(id: 2, startTime: iso(Date()))])
        // Swap the API by creating a new SUT with good API (viewmodel API is injected at init).
        let sut2 = AppointmentsThreeColumnViewModel(api: goodAPI)
        await sut2.load()
        XCTAssertNil(sut2.errorMessage)
    }

    // MARK: - scopeAppointments: today

    func test_scopeAppointments_today_returnsOnlyTodayAppointments() async {
        let today = makeAppointment(id: 1, startTime: iso(Date()))
        let tomorrow = makeAppointment(id: 2, startTime: iso(Date(timeIntervalSinceNow: 86_400)))
        let api = ThreeColStubAPI(appointments: [today, tomorrow])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedScope = .today
        let result = sut.scopeAppointments
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func test_scopeAppointments_today_emptyWhenNoneToday() async {
        let tomorrow = makeAppointment(id: 2, startTime: iso(Date(timeIntervalSinceNow: 86_400)))
        let api = ThreeColStubAPI(appointments: [tomorrow])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedScope = .today
        XCTAssertTrue(sut.scopeAppointments.isEmpty)
    }

    // MARK: - scopeAppointments: all

    func test_scopeAppointments_all_returnsAllAppointments() async {
        let appts = [
            makeAppointment(id: 1, startTime: iso(Date())),
            makeAppointment(id: 2, startTime: iso(Date(timeIntervalSinceNow: 86_400))),
            makeAppointment(id: 3, startTime: iso(Date(timeIntervalSinceNow: -86_400))),
        ]
        let api = ThreeColStubAPI(appointments: appts)
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedScope = .all
        XCTAssertEqual(sut.scopeAppointments.count, 3)
    }

    func test_scopeAppointments_all_sortedByStartTimeAscending() async {
        let later  = makeAppointment(id: 2, startTime: iso(Date(timeIntervalSinceNow: 3600)))
        let earlier = makeAppointment(id: 1, startTime: iso(Date()))
        let api = ThreeColStubAPI(appointments: [later, earlier])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedScope = .all
        let ids = sut.scopeAppointments.map(\.id)
        XCTAssertEqual(ids, [1, 2])
    }

    // MARK: - dayAgendaAppointments

    func test_dayAgendaAppointments_returnsSelectedDateOnly() async {
        let today = makeAppointment(id: 1, startTime: iso(Date()))
        let tomorrow = makeAppointment(id: 2, startTime: iso(Date(timeIntervalSinceNow: 86_400)))
        let api = ThreeColStubAPI(appointments: [today, tomorrow])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedDate = Date()
        let result = sut.dayAgendaAppointments
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func test_dayAgendaAppointments_emptyForDateWithNoAppointments() async {
        let today = makeAppointment(id: 1, startTime: iso(Date()))
        let api = ThreeColStubAPI(appointments: [today])
        let sut = makeSUT(api: api)
        await sut.load()
        // Set selected date to a past date with no appointments.
        sut.selectedDate = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(sut.dayAgendaAppointments.isEmpty)
    }

    // MARK: - parseDate

    func test_parseDate_iso8601_succeeds() {
        let result = AppointmentsThreeColumnViewModel.parseDate("2025-06-02T09:00:00Z")
        XCTAssertNotNil(result)
    }

    func test_parseDate_sqlFormat_succeeds() {
        let result = AppointmentsThreeColumnViewModel.parseDate("2025-06-02 09:00:00")
        XCTAssertNotNil(result)
    }

    func test_parseDate_invalid_returnsNil() {
        let result = AppointmentsThreeColumnViewModel.parseDate("not-a-date")
        XCTAssertNil(result)
    }

    func test_parseDate_emptyString_returnsNil() {
        let result = AppointmentsThreeColumnViewModel.parseDate("")
        XCTAssertNil(result)
    }

    // MARK: - selectedScope state transitions

    func test_selectedScope_canBeChanged() {
        let sut = makeSUT()
        sut.selectedScope = .week
        XCTAssertEqual(sut.selectedScope, .week)
        sut.selectedScope = .month
        XCTAssertEqual(sut.selectedScope, .month)
    }

    func test_selectedAppointment_canBeSet() async {
        let appt = makeAppointment(id: 42, startTime: iso(Date()))
        let api = ThreeColStubAPI(appointments: [appt])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedAppointment = appt
        XCTAssertEqual(sut.selectedAppointment?.id, 42)
    }

    func test_selectedAppointment_canBeCleared() async {
        let appt = makeAppointment(id: 42, startTime: iso(Date()))
        let api = ThreeColStubAPI(appointments: [appt])
        let sut = makeSUT(api: api)
        await sut.load()
        sut.selectedAppointment = appt
        sut.selectedAppointment = nil
        XCTAssertNil(sut.selectedAppointment)
    }

    // MARK: - AppointmentsScopeFilter

    func test_scopeFilter_allCasesExist() {
        let cases = AppointmentsScopeFilter.allCases
        XCTAssertTrue(cases.contains(.today))
        XCTAssertTrue(cases.contains(.week))
        XCTAssertTrue(cases.contains(.month))
        XCTAssertTrue(cases.contains(.all))
    }

    func test_scopeFilter_idsAreRawValues() {
        XCTAssertEqual(AppointmentsScopeFilter.today.id, AppointmentsScopeFilter.today.rawValue)
    }

    // MARK: - Helpers

    private func makeSUT(api: APIClient? = nil) -> AppointmentsThreeColumnViewModel {
        AppointmentsThreeColumnViewModel(api: api ?? ThreeColStubAPI(appointments: []))
    }

    private func makeAppointment(id: Int64, startTime: String) -> Appointment {
        let dict: [String: Any] = [
            "id": id,
            "title": "Appt \(id)",
            "start_time": startTime,
            "status": "scheduled"
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    /// Produces an ISO-8601 string for the given date (UTC).
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// MARK: - ThreeColStubAPI

private actor ThreeColStubAPI: APIClient {
    private let appointments: [Appointment]
    private let error: Error?

    init(appointments: [Appointment], error: Error? = nil) {
        self.appointments = appointments
        self.error = error
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let e = error { throw e }
        if path.contains("/appointments") {
            let resp = AppointmentsListResponse(appointments: appointments)
            guard let t = resp as? T else { throw APITransportError.decoding("type mismatch") }
            return t
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
