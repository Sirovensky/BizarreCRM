import XCTest
@testable import Appointments
import Networking
import Core

// MARK: - AppointmentEditViewModelTests
// TDD: tests written before AppointmentEditViewModel was finalised.

@MainActor
final class AppointmentEditViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeAppointment(
        id: Int64 = 1,
        title: String = "Device pickup",
        startTime: String = "2025-06-01T09:00:00Z",
        endTime: String = "2025-06-01T10:00:00Z",
        status: String = "scheduled",
        notes: String? = nil
    ) -> Appointment {
        var dict: [String: Any] = [
            "id": id,
            "title": title,
            "start_time": startTime,
            "end_time": endTime,
            "status": status
        ]
        if let notes { dict["notes"] = notes }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    private func makeSlot(offsetHours: Double) -> AvailabilitySlot {
        let fmt = ISO8601DateFormatter()
        let base = Date(timeIntervalSince1970: 1_748_779_200) // 2025-06-01 12:00 UTC
        return AvailabilitySlot(
            start: fmt.string(from: base.addingTimeInterval(offsetHours * 3600)),
            end: fmt.string(from: base.addingTimeInterval((offsetHours + 1) * 3600))
        )
    }

    private func makeSUT(
        appt: Appointment? = nil,
        updateResult: Result<Appointment, Error> = .success(makeMinimalAppt())
    ) -> (AppointmentEditViewModel, EditStubAPIClient) {
        let appointment = appt ?? makeAppointment()
        let api = EditStubAPIClient(updateResult: updateResult)
        let vm = AppointmentEditViewModel(appointment: appointment, api: api)
        return (vm, api)
    }

    private static func makeMinimalAppt() -> Appointment {
        let dict: [String: Any] = ["id": 1, "title": "Updated", "status": "scheduled"]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(Appointment.self, from: data)
    }

    // MARK: - Pre-population

    func test_init_prePopulatesTitle() {
        let (vm, _) = makeSUT(appt: makeAppointment(title: "Consult — Alice"))
        XCTAssertEqual(vm.title, "Consult — Alice")
    }

    func test_init_prePopulatesNotes() {
        let (vm, _) = makeSUT(appt: makeAppointment(notes: "Bring phone"))
        XCTAssertEqual(vm.notes, "Bring phone")
    }

    func test_init_parsesStartDateFromISO() {
        let (vm, _) = makeSUT(appt: makeAppointment(startTime: "2025-08-15T14:30:00Z"))
        let cal = Calendar.current
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: vm.selectedDate)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }

    // MARK: - Validation

    func test_isValid_titleEmpty_false() {
        let (vm, _) = makeSUT()
        vm.title = ""
        XCTAssertFalse(vm.isValid)
    }

    func test_isValid_titleNonEmpty_true() {
        let (vm, _) = makeSUT()
        vm.title = "Any Title"
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Submit — happy path

    func test_submit_happyPath_setsUpdatedAppointment() async {
        let updated = makeMinimalAppt()
        let (vm, _) = makeSUT(updateResult: .success(updated))
        XCTAssertNil(vm.updatedAppointment)
        await vm.submit()
        XCTAssertNotNil(vm.updatedAppointment)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_clearsErrorOnSuccess() async {
        let (vm, _) = makeSUT()
        await vm.submit()
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Submit — error path

    func test_submit_apiError_setsErrorMessage() async {
        let (vm, _) = makeSUT(updateResult: .failure(APITransportError.httpStatus(403, message: nil)))
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.updatedAppointment)
    }

    func test_submit_conflict409_setsConflictMessage() async {
        let (vm, _) = makeSUT(
            updateResult: .failure(APITransportError.httpStatus(409, message: "Double-booked"))
        )
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_submit_offline_setsOfflineMessage() async {
        let urlError = URLError(.notConnectedToInternet)
        let (vm, _) = makeSUT(updateResult: .failure(urlError))
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Idempotency guard

    func test_submit_doubleCall_doesNotDoubleSubmit() async {
        let (vm, api) = makeSUT()
        async let first: () = vm.submit()
        async let second: () = vm.submit()
        _ = await (first, second)
        XCTAssertLessThanOrEqual(api.putCallCount, 1)
    }

    // MARK: - Empty title guard

    func test_submit_emptyTitle_setsError_noNetworkCall() async {
        let (vm, api) = makeSUT()
        vm.title = ""
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(api.putCallCount, 0)
    }

    // MARK: - Slot selection

    func test_selectSlot_noConflict_warningFalse() {
        let (vm, _) = makeSUT()
        let slot = makeSlot(offsetHours: 3)
        vm.selectSlot(slot)
        XCTAssertEqual(vm.selectedSlot?.id, slot.id)
        XCTAssertFalse(vm.conflictWarning)
    }

    func test_selectSlot_conflicting_warningTrue() {
        let (vm, _) = makeSUT()
        let slot = makeSlot(offsetHours: 2)
        vm.conflictingSlots = [slot.id]
        vm.selectSlot(slot)
        XCTAssertTrue(vm.conflictWarning)
    }

    // MARK: - Load employees

    func test_loadEmployees_populatesEmployeeList() async {
        let emp = makeEmployee(id: 42, name: "Bob")
        let api = EditStubAPIClient(updateResult: .success(Self.makeMinimalAppt()), employees: [emp])
        let vm = AppointmentEditViewModel(appointment: makeAppointment(), api: api)
        await vm.loadEmployees()
        XCTAssertEqual(vm.employees.count, 1)
        XCTAssertEqual(vm.employees.first?.id, 42)
    }

    // MARK: - Excludes-self conflict check (regression)

    func test_loadAvailability_excludesSelfFromConflictCheck() async {
        // The appointment being edited should not conflict with itself.
        // If we're editing id=1 on the same date/time, it should NOT show as conflict.
        let appt = makeAppointment(id: 1, startTime: "2025-06-01T09:00:00Z", endTime: "2025-06-01T10:00:00Z")
        let fmt = ISO8601DateFormatter()
        let selfSlot = AvailabilitySlot(
            start: fmt.string(from: Date(timeIntervalSince1970: 1_748_779_200)),
            end: fmt.string(from: Date(timeIntervalSince1970: 1_748_782_800))
        )
        // Stub returns the appointment itself as existing — should be excluded
        let api = EditStubAPIClient(
            updateResult: .success(Self.makeMinimalAppt()),
            existingAppointments: [appt],
            slots: [selfSlot]
        )
        let vm = AppointmentEditViewModel(appointment: appt, api: api)
        vm.technicianId = 1
        await vm.loadAvailability()
        // selfSlot should NOT appear in conflicting since the only "existing" appt is self
        XCTAssertFalse(vm.conflictingSlots.contains(selfSlot.id),
            "Self-appointment must be excluded from conflict detection")
    }

    // MARK: - Private helpers

    private func makeEmployee(id: Int64, name: String) -> Employee {
        let dict: [String: Any] = ["id": id, "first_name": name]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Employee.self, from: data)
    }
}

// MARK: - EditStubAPIClient

private actor EditStubAPIClient: APIClient {
    let employees: [Employee]
    let slots: [AvailabilitySlot]
    let existingAppointments: [Appointment]
    let updateResult: Result<Appointment, Error>
    private(set) var putCallCount: Int = 0

    init(
        updateResult: Result<Appointment, Error>,
        employees: [Employee] = [],
        existingAppointments: [Appointment] = [],
        slots: [AvailabilitySlot] = []
    ) {
        self.updateResult = updateResult
        self.employees = employees
        self.existingAppointments = existingAppointments
        self.slots = slots
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/employees") && !path.contains("/availability") {
            guard let t = employees as? T else { throw APITransportError.decoding("type") }
            return t
        }
        if path.contains("/availability") {
            let resp = EmployeeAvailabilityResponse(slots: slots)
            guard let t = resp as? T else { throw APITransportError.decoding("type") }
            return t
        }
        if path.contains("/appointments") {
            let resp = AppointmentsListResponse(appointments: existingAppointments)
            guard let t = resp as? T else { throw APITransportError.decoding("type") }
            return t
        }
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
