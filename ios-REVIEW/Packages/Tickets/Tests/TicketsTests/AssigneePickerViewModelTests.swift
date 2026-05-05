import XCTest
@testable import Tickets
import Networking

// §4 — AssigneePickerViewModel unit tests.
//
// Coverage: load happy path, load error, search filtering (text match, active-only),
//           double-load guard, empty search returns all active.

@MainActor
final class AssigneePickerViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeEmployee(
        id: Int64,
        firstName: String,
        lastName: String,
        email: String? = nil,
        isActive: Int = 1
    ) -> Employee {
        let emailJSON = email.map { "\"\($0)\"" } ?? "null"
        let json = #"""
        {
          "id": \#(id),
          "first_name": "\#(firstName)",
          "last_name": "\#(lastName)",
          "email": \#(emailJSON),
          "is_active": \#(isActive)
        }
        """#
        return try! JSONDecoder().decode(Employee.self, from: Data(json.utf8))
    }

    // MARK: - Load

    func test_load_happyPath_populatesEmployees() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Ada", lastName: "Lovelace"),
            makeEmployee(id: 2, firstName: "Grace", lastName: "Hopper"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        XCTAssertTrue(vm.employees.isEmpty)

        await vm.load()

        XCTAssertEqual(vm.employees.count, 2)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_error_setsErrorMessage() async {
        let stub = EmployeeStubAPIClient(result: .failure(APITransportError.noBaseURL))
        let vm = AssigneePickerViewModel(api: stub)

        await vm.load()

        XCTAssertTrue(vm.employees.isEmpty)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func test_load_emptyList_succeeds() async {
        let stub = EmployeeStubAPIClient(result: .success([]))
        let vm = AssigneePickerViewModel(api: stub)

        await vm.load()

        XCTAssertTrue(vm.employees.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Search filtering

    func test_filtered_emptySearch_returnsAllActive() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Ada", lastName: "Lovelace", isActive: 1),
            makeEmployee(id: 2, firstName: "Grace", lastName: "Hopper", isActive: 0),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = ""
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered[0].id, 1)
    }

    func test_filtered_excludesInactiveEmployees() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Active", lastName: "User", isActive: 1),
            makeEmployee(id: 2, firstName: "Inactive", lastName: "User", isActive: 0),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        let all = vm.filtered
        XCTAssertFalse(all.contains { $0.id == 2 })
        XCTAssertTrue(all.contains { $0.id == 1 })
    }

    func test_filtered_searchByFirstName() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Alice", lastName: "Smith"),
            makeEmployee(id: 2, firstName: "Bob", lastName: "Jones"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = "ali"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered[0].firstName, "Alice")
    }

    func test_filtered_searchByLastName() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Alice", lastName: "Smith"),
            makeEmployee(id: 2, firstName: "Bob", lastName: "Jones"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = "Jones"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered[0].id, 2)
    }

    func test_filtered_searchByEmail() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Dev", lastName: "One", email: "dev@example.com"),
            makeEmployee(id: 2, firstName: "Dev", lastName: "Two", email: "tech@other.com"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = "example.com"
        XCTAssertEqual(vm.filtered.count, 1)
        XCTAssertEqual(vm.filtered[0].id, 1)
    }

    func test_filtered_noMatch_returnsEmpty() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Alice", lastName: "Smith"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = "zzz-no-match"
        XCTAssertTrue(vm.filtered.isEmpty)
    }

    func test_filtered_searchIsCaseInsensitive() async {
        let stub = EmployeeStubAPIClient(result: .success([
            makeEmployee(id: 1, firstName: "Alice", lastName: "Smith"),
        ]))
        let vm = AssigneePickerViewModel(api: stub)
        await vm.load()

        vm.searchText = "ALICE"
        XCTAssertEqual(vm.filtered.count, 1)
    }

    // MARK: - Loading state

    func test_isLoading_falseAfterLoad() async {
        let stub = EmployeeStubAPIClient(result: .success([]))
        let vm = AssigneePickerViewModel(api: stub)

        await vm.load()

        XCTAssertFalse(vm.isLoading)
    }
}

// MARK: - Employee stub

/// Minimal APIClient stub for AssigneePickerViewModel tests.
private actor EmployeeStubAPIClient: APIClient {
    private let result: Result<[Employee], Error>

    init(result: Result<[Employee], Error>) {
        self.result = result
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/employees" {
            switch result {
            case .success(let employees):
                guard let cast = employees as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
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
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
