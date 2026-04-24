import XCTest
@testable import Employees
@testable import Networking

// MARK: - EmployeeListFilterTests

@MainActor
final class EmployeeListFilterTests: XCTestCase {

    // MARK: - isDefault

    func test_defaultFilter_isDefault() {
        XCTAssertTrue(EmployeeListFilter().isDefault)
    }

    func test_roleSet_notDefault() {
        XCTAssertFalse(EmployeeListFilter(role: "admin").isDefault)
    }

    func test_showInactiveTrue_notDefault() {
        XCTAssertFalse(EmployeeListFilter(showInactive: true).isDefault)
    }

    func test_searchQuery_notDefault() {
        XCTAssertFalse(EmployeeListFilter(searchQuery: "alice").isDefault)
    }

    func test_locationId_notDefault() {
        XCTAssertFalse(EmployeeListFilter(locationId: 2).isDefault)
    }

    // MARK: - Equality

    func test_equalFilters() {
        let a = EmployeeListFilter(role: "manager", locationId: 1, showInactive: true, searchQuery: "bob")
        let b = EmployeeListFilter(role: "manager", locationId: 1, showInactive: true, searchQuery: "bob")
        XCTAssertEqual(a, b)
    }

    func test_differentRole_notEqual() {
        XCTAssertNotEqual(EmployeeListFilter(role: "admin"), EmployeeListFilter(role: "manager"))
    }

    // MARK: - EmployeeListViewModel filter application

    func test_filter_byRole_keepsMatchingOnly() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, role: "admin"),
            makeEmp(id: 2, role: "technician"),
            makeEmp(id: 3, role: "admin"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(role: "admin")
        XCTAssertEqual(vm.filteredItems.map { $0.id }, [1, 3])
    }

    func test_filter_searchQuery_matchesName() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, firstName: "Alice", lastName: "Smith"),
            makeEmp(id: 2, firstName: "Bob",   lastName: "Jones"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(searchQuery: "ali")
        XCTAssertEqual(vm.filteredItems.map { $0.id }, [1])
    }

    func test_filter_searchQuery_matchesEmail() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, email: "alice@example.com"),
            makeEmp(id: 2, email: "bob@example.com"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(searchQuery: "bob@")
        XCTAssertEqual(vm.filteredItems.map { $0.id }, [2])
    }

    func test_filter_showInactive_false_hidesInactive() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, isActive: 1),
            makeEmp(id: 2, isActive: 0),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(showInactive: false)
        XCTAssertEqual(vm.filteredItems.map { $0.id }, [1])
    }

    func test_filter_showInactive_true_includesBoth() async {
        let both = [makeEmp(id: 1, isActive: 1), makeEmp(id: 2, isActive: 0)]
        let api = StubListAPI(employees: both, allUsers: both)
        let vm = EmployeeListViewModel(api: api)
        vm.filter = EmployeeListFilter(showInactive: true)
        await vm.load()
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func test_clearFilter_restoresAll() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, role: "admin"),
            makeEmp(id: 2, role: "technician"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(role: "admin")
        XCTAssertEqual(vm.filteredItems.count, 1)
        vm.filter = .init()
        XCTAssertEqual(vm.filteredItems.count, 2)
    }

    func test_availableRoles_populatedAfterLoad() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, role: "admin"),
            makeEmp(id: 2, role: "technician"),
            makeEmp(id: 3, role: "admin"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        XCTAssertEqual(Set(vm.availableRoles), Set(["admin", "technician"]))
    }

    func test_loadError_setsErrorMessage() async {
        let api = StubListAPI(error: APITransportError.noBaseURL)
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_searchQuery_caseInsensitive() async {
        let api = StubListAPI(employees: [
            makeEmp(id: 1, firstName: "ALICE"),
            makeEmp(id: 2, firstName: "Bob"),
        ])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(searchQuery: "alice")
        XCTAssertEqual(vm.filteredItems.map { $0.id }, [1])
    }

    func test_emptySearch_returnsAll() async {
        let api = StubListAPI(employees: [makeEmp(id: 1), makeEmp(id: 2)])
        let vm = EmployeeListViewModel(api: api)
        await vm.load()
        vm.filter = EmployeeListFilter(searchQuery: "")
        XCTAssertEqual(vm.filteredItems.count, 2)
    }
}

// MARK: - Stub

private final class StubListAPI: APIClient, @unchecked Sendable {
    private let employees: [Employee]
    private let allUsers: [Employee]
    private let error: Error?

    init(employees: [Employee] = [], allUsers: [Employee] = [], error: Error? = nil) {
        self.employees = employees
        self.allUsers = allUsers.isEmpty ? employees : allUsers
        self.error = error
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if let err = error { throw err }
        if path == "/api/v1/employees" {
            guard let cast = employees as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        if path == "/api/v1/settings/users" {
            guard let cast = allUsers as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.notImplemented
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.notImplemented }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.notImplemented }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.notImplemented }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// MARK: - Factory helper

/// Creates an Employee with extended fields (role/email/isActive).
/// The base Employee.fixture(id:firstName:lastName:) is declared in
/// EmployeeCachedRepositoryTests — this private func avoids re-declaration.
private func makeEmp(
    id: Int64 = 1,
    firstName: String = "Alice",
    lastName: String = "Smith",
    role: String? = nil,
    email: String? = nil,
    isActive: Int = 1
) -> Employee {
    var dict: [String: Any] = [
        "id":         id,
        "first_name": firstName,
        "last_name":  lastName,
        "is_active":  isActive,
    ]
    if let r = role  { dict["role"]  = r }
    if let e = email { dict["email"] = e }
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(Employee.self, from: data)
}
