import XCTest
@testable import Appointments
import Networking
import Core

// MARK: - AppointmentCreateFullViewModelTests

@MainActor
final class AppointmentCreateFullViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeSUT(
        employees: [Employee] = [],
        slots: [AvailabilitySlot] = [],
        createResult: Result<CreatedResource, Error> = .success(.init(id: 77))
    ) -> (AppointmentCreateFullViewModel, ApptStubAPIClient) {
        let api = ApptStubAPIClient(employees: employees, slots: slots, createResult: createResult)
        return (AppointmentCreateFullViewModel(api: api), api)
    }

    private func makeSlot(offsetHours: Double) -> AvailabilitySlot {
        let fmt = ISO8601DateFormatter()
        let base = Date(timeIntervalSince1970: 1_700_050_000)
        return AvailabilitySlot(
            start: fmt.string(from: base.addingTimeInterval(offsetHours * 3600)),
            end: fmt.string(from: base.addingTimeInterval((offsetHours + 1) * 3600))
        )
    }

    // MARK: - Initial state

    func test_initialState() {
        let (vm, _) = makeSUT()
        XCTAssertFalse(vm.isValid)
        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.isSubmitting)
    }

    // MARK: - Validation

    func test_isValid_requiresCustomerAndSlot() {
        let (vm, _) = makeSUT()
        vm.customerId = 1
        XCTAssertFalse(vm.isValid, "No slot → invalid")

        vm.selectedSlot = makeSlot(offsetHours: 1)
        XCTAssertTrue(vm.isValid, "Customer + slot → valid")
    }

    // MARK: - Submit without customer

    func test_submit_withoutCustomer_setsError() async {
        let (vm, _) = makeSUT()
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.createdId)
    }

    // MARK: - Submit without slot

    func test_submit_withoutSlot_setsError() async {
        let (vm, _) = makeSUT()
        vm.customerId = 1
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Happy path

    func test_submit_happyPath_setsCreatedId() async {
        let (vm, _) = makeSUT(createResult: .success(.init(id: 100)))
        vm.customerId = 5
        vm.selectedSlot = makeSlot(offsetHours: 2)
        await vm.submit()
        XCTAssertEqual(vm.createdId, 100)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - API error

    func test_submit_conflict_showsMessage() async {
        let (vm, _) = makeSUT(createResult: .failure(APITransportError.httpStatus(409, message: nil)))
        vm.customerId = 3
        vm.selectedSlot = makeSlot(offsetHours: 1)
        await vm.submit()
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - Load employees

    func test_loadEmployees_populatesEmployees() async {
        let emp = makeEmployee(id: 1, name: "Alice")
        let (vm, _) = makeSUT(employees: [emp])
        await vm.loadEmployees()
        XCTAssertEqual(vm.employees.count, 1)
        XCTAssertEqual(vm.employees.first?.id, 1)
    }

    // MARK: - Service type

    func test_serviceTypeDefault_dropOff() {
        let (vm, _) = makeSUT()
        XCTAssertEqual(vm.serviceType, .dropOff)
    }

    // MARK: - Slot selection + conflict warning

    func test_selectSlot_noConflict_warningFalse() {
        let (vm, _) = makeSUT()
        let slot = makeSlot(offsetHours: 5)
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

    // MARK: - Draft save

    func test_scheduleDraftSave_setsDraftSavedAt() async {
        let (vm, _) = makeSUT()
        vm.scheduleDraftSave()
        // Wait for 600ms debounce
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertNotNil(vm.draftSavedAt)
    }

    // MARK: - Helpers

    private func makeEmployee(id: Int64, name: String) -> Employee {
        let dict: [String: Any] = ["id": id, "first_name": name]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(Employee.self, from: data)
    }
}

// MARK: - ApptStubAPIClient

private actor ApptStubAPIClient: APIClient {
    let employees: [Employee]
    let slots: [AvailabilitySlot]
    let createResult: Result<CreatedResource, Error>

    init(employees: [Employee], slots: [AvailabilitySlot], createResult: Result<CreatedResource, Error>) {
        self.employees = employees
        self.slots = slots
        self.createResult = createResult
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
            let resp = AppointmentsListResponse(appointments: [])
            guard let t = resp as? T else { throw APITransportError.decoding("type") }
            return t
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        switch createResult {
        case .success(let r):
            guard let t = r as? T else { throw APITransportError.decoding("type") }
            return t
        case .failure(let e):
            throw e
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) {}
    func setBaseURL(_ url: URL?) {}
    func currentBaseURL() -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) {}
}
