import XCTest
@testable import Appointments
import Networking

// MARK: - AppointmentCalendarGridViewModelTests

@MainActor
final class AppointmentCalendarGridViewModelTests: XCTestCase {

    // MARK: - startOfWeek

    func test_startOfWeek_returnsMonday() {
        // 2025-06-04 is a Wednesday
        let wednesday = Date(timeIntervalSince1970: 1_748_995_200) // 2025-06-04 00:00 UTC
        let monday = AppointmentCalendarGridViewModel.startOfWeek(for: wednesday)
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2, "startOfWeek must return Monday (weekday=2)")
    }

    func test_startOfWeek_mondayInputReturnsSelf() {
        // 2025-06-02 is a Monday
        let monday = Date(timeIntervalSince1970: 1_748_822_400) // 2025-06-02 00:00 UTC
        let result = AppointmentCalendarGridViewModel.startOfWeek(for: monday)
        let cal = Calendar(identifier: .gregorian)
        XCTAssertEqual(cal.component(.weekday, from: result), 2)
    }

    // MARK: - weekDays

    func test_weekDays_returnsSevenDays() {
        let sut = makeSUT()
        XCTAssertEqual(sut.weekDays.count, 7)
    }

    func test_weekDays_firstDayIsMonday() {
        let sut = makeSUT()
        let cal = Calendar(identifier: .gregorian)
        let firstDay = try! XCTUnwrap(sut.weekDays.first)
        XCTAssertEqual(cal.component(.weekday, from: firstDay), 2,
            "First column must be Monday")
    }

    func test_weekDays_lastDayIsSunday() {
        let sut = makeSUT()
        let cal = Calendar(identifier: .gregorian)
        let lastDay = try! XCTUnwrap(sut.weekDays.last)
        XCTAssertEqual(cal.component(.weekday, from: lastDay), 1,
            "Last column must be Sunday")
    }

    // MARK: - previousWeek / nextWeek

    func test_previousWeek_movesBackSevenDays() {
        let sut = makeSUT()
        let original = sut.weekStart
        sut.previousWeek()
        let diff = original.timeIntervalSince(sut.weekStart)
        XCTAssertEqual(diff, 7 * 24 * 3600, accuracy: 1)
    }

    func test_nextWeek_movesForwardSevenDays() {
        let sut = makeSUT()
        let original = sut.weekStart
        sut.nextWeek()
        let diff = sut.weekStart.timeIntervalSince(original)
        XCTAssertEqual(diff, 7 * 24 * 3600, accuracy: 1)
    }

    func test_goToToday_snapsToThisWeekMonday() {
        let sut = makeSUT()
        sut.nextWeek()
        sut.nextWeek()
        sut.goToToday()
        let today = Date()
        let cal = Calendar(identifier: .gregorian)
        let expectedMonday = AppointmentCalendarGridViewModel.startOfWeek(for: today)
        XCTAssertEqual(
            cal.startOfDay(for: sut.weekStart),
            cal.startOfDay(for: expectedMonday)
        )
    }

    // MARK: - appointments(on:) filtering

    func test_appointmentsOnDay_returnsOnlyMatchingDay() async {
        // 2025-06-02 09:00 UTC (Monday)
        let mondayAppt = makeAppointment(id: 1, startTime: "2025-06-02T09:00:00Z")
        // 2025-06-03 10:00 UTC (Tuesday)
        let tuesdayAppt = makeAppointment(id: 2, startTime: "2025-06-03T10:00:00Z")
        let api = GridStubAPI(appointments: [mondayAppt, tuesdayAppt])
        let sut = makeSUT(api: api)
        await sut.load()

        let monday = Date(timeIntervalSince1970: 1_748_822_400) // 2025-06-02 00:00 UTC
        let result = sut.appointments(on: monday)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, 1)
    }

    func test_appointmentsOnDay_sortedByStartTime() async {
        // Two appointments on the same day, inserted in reverse order.
        let later  = makeAppointment(id: 2, startTime: "2025-06-02T11:00:00Z")
        let earlier = makeAppointment(id: 1, startTime: "2025-06-02T09:00:00Z")
        let api = GridStubAPI(appointments: [later, earlier])
        let sut = makeSUT(api: api)
        await sut.load()

        let monday = Date(timeIntervalSince1970: 1_748_822_400)
        let result = sut.appointments(on: monday)
        XCTAssertEqual(result.map(\.id), [1, 2], "Appointments must be sorted by start time ascending")
    }

    func test_appointmentsOnDay_noAppointments_returnsEmpty() async {
        let api = GridStubAPI(appointments: [])
        let sut = makeSUT(api: api)
        await sut.load()

        let monday = Date(timeIntervalSince1970: 1_748_822_400)
        XCTAssertTrue(sut.appointments(on: monday).isEmpty)
    }

    func test_appointmentsOnDay_sqlDateFormat_parsed() async {
        // SQL-format date should also be handled.
        let appt = makeAppointment(id: 3, startTime: "2025-06-02 09:00:00")
        let api = GridStubAPI(appointments: [appt])
        let sut = makeSUT(api: api)
        await sut.load()

        let monday = Date(timeIntervalSince1970: 1_748_822_400)
        let result = sut.appointments(on: monday)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - isToday

    func test_isToday_trueForToday() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isToday(Date()))
    }

    func test_isToday_falseForTomorrow() {
        let sut = makeSUT()
        let tomorrow = Date(timeIntervalSinceNow: 86_400)
        XCTAssertFalse(sut.isToday(tomorrow))
    }

    // MARK: - load error path

    func test_load_apiError_setsErrorMessage() async {
        let api = GridStubAPI(error: APITransportError.noBaseURL)
        let sut = makeSUT(api: api)
        await sut.load()
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.appointments.isEmpty)
    }

    // MARK: - parseDate

    func test_parseDate_iso8601_returnsDate() {
        let result = AppointmentCalendarGridViewModel.parseDate("2025-06-02T09:00:00Z")
        XCTAssertNotNil(result)
    }

    func test_parseDate_sqlFormat_returnsDate() {
        let result = AppointmentCalendarGridViewModel.parseDate("2025-06-02 09:00:00")
        XCTAssertNotNil(result)
    }

    func test_parseDate_garbage_returnsNil() {
        let result = AppointmentCalendarGridViewModel.parseDate("not-a-date")
        XCTAssertNil(result)
    }

    // MARK: - Private helpers

    private func makeSUT(api: APIClient? = nil) -> AppointmentCalendarGridViewModel {
        // Pin reference date to 2025-06-04 (Wednesday) so weekStart = 2025-06-02 (Monday)
        let referenceDate = Date(timeIntervalSince1970: 1_748_995_200)
        let apiClient = api ?? GridStubAPI(appointments: [])
        return AppointmentCalendarGridViewModel(api: apiClient, referenceDate: referenceDate)
    }

    private func makeAppointment(id: Int64, startTime: String) -> Appointment {
        let dict: [String: Any] = ["id": id, "title": "Test \(id)", "start_time": startTime, "status": "scheduled"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }
}

// MARK: - GridStubAPI

private actor GridStubAPI: APIClient {
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
