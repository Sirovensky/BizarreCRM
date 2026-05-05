import XCTest
@testable import Employees
@testable import Networking

// MARK: - InviteEmployeeViewModelTests
// §14.4 Invite tests — covers validation + API call path.

@MainActor
final class InviteEmployeeViewModelTests: XCTestCase {

    // MARK: - Validation

    func testIsValidRequiresFirstNameLastNameUsername() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        XCTAssertFalse(vm.isValid, "Empty form must be invalid")
        vm.firstName = "Jane"
        XCTAssertFalse(vm.isValid)
        vm.lastName = "Smith"
        XCTAssertFalse(vm.isValid)
        vm.username = "jsmith"
        XCTAssertTrue(vm.isValid, "All required fields filled → valid")
    }

    func testIsInvalidWhenPasswordTooShort() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        vm.firstName = "Jane"; vm.lastName = "Smith"; vm.username = "jsmith"
        vm.password = "short"   // < 8 chars
        XCTAssertFalse(vm.isValid, "Password < 8 chars → invalid")
    }

    func testIsValidWhenPasswordExactly8Chars() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        vm.firstName = "Jane"; vm.lastName = "Smith"; vm.username = "jsmith"
        vm.password = "abcdefgh"  // exactly 8
        XCTAssertTrue(vm.isValid)
    }

    // MARK: - Username derivation

    func testDeriveUsernameFromFirstAndLastName() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        vm.firstName = "Jane"
        vm.lastName = "Smith"
        vm.deriveUsername()
        XCTAssertEqual(vm.username, "janesmith")
    }

    func testDeriveUsernameDoesNotOverrideExistingUsername() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        vm.username = "existing"
        vm.firstName = "Jane"
        vm.lastName = "Smith"
        vm.deriveUsername()
        XCTAssertEqual(vm.username, "existing", "Should not overwrite existing username")
    }

    // MARK: - Submit

    func testSubmitSetsCreatedEmployee() async {
        let mock = MockAPIClient()
        mock.outcome = .success
        let vm = InviteEmployeeViewModel(api: mock)
        vm.firstName = "Jane"; vm.lastName = "Smith"; vm.username = "jsmith"
        await vm.submit()
        XCTAssertNotNil(vm.createdEmployee)
        XCTAssertNil(vm.submitError)
    }

    func testSubmitSetsErrorOnFailure() async {
        let mock = MockAPIClient()
        mock.outcome = .failure
        let vm = InviteEmployeeViewModel(api: mock)
        vm.firstName = "Jane"; vm.lastName = "Smith"; vm.username = "jsmith"
        await vm.submit()
        XCTAssertNil(vm.createdEmployee)
        XCTAssertNotNil(vm.submitError)
    }

    func testSubmitDoesNothingWhenInvalid() async {
        let mock = MockAPIClient()
        let vm = InviteEmployeeViewModel(api: mock)
        // Form is empty — invalid
        await vm.submit()
        XCTAssertEqual(mock.postCallCount, 0)
    }

    func testEmailOptionalInBody() async {
        let mock = MockAPIClient()
        mock.outcome = .success
        let vm = InviteEmployeeViewModel(api: mock)
        vm.firstName = "Jane"; vm.lastName = "Smith"; vm.username = "jsmith"
        vm.email = ""  // empty = should pass nil to API
        await vm.submit()
        XCTAssertNotNil(vm.createdEmployee, "Should succeed even without email")
    }

    func testDefaultRole() {
        let vm = InviteEmployeeViewModel(api: MockAPIClient())
        XCTAssertEqual(vm.role, "technician")
    }
}

// MARK: - Mock

private actor MockAPIClient: APIClient {
    enum Outcome { case success, failure }
    var outcome: Outcome = .success
    private(set) var postCallCount: Int = 0

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        postCallCount += 1
        switch outcome {
        case .success:
            let emp = Employee.fixture()
            guard let cast = emp as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        case .failure:
            throw APITransportError.noBaseURL
        }
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

// MARK: - Employee fixture

private extension Employee {
    static func fixture() -> Employee {
        let data = try! JSONSerialization.data(withJSONObject: [
            "id": 42,
            "username": "jsmith",
            "first_name": "Jane",
            "last_name": "Smith",
            "role": "technician",
            "is_active": 1
        ])
        return try! JSONDecoder().decode(Employee.self, from: data)
    }
}
