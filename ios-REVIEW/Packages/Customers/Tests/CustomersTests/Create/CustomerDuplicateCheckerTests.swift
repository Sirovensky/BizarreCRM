import XCTest
@testable import Customers
import Networking

// MARK: - §5.3 Duplicate detection unit tests

@MainActor
final class CustomerDuplicateCheckerTests: XCTestCase {

    // MARK: findDuplicate — email match

    func test_emailMatch_exactLowercase_returnsCandidate() async {
        let alice = CustomerSummary.stub(id: 1, email: "alice@example.com", phone: nil)
        let api = ListCustomersStubAPI(response: [alice])
        let checker = CustomerDuplicateChecker(api: api)

        let result = await checker.findDuplicate(phone: "", email: "ALICE@example.com")

        XCTAssertEqual(result?.id, 1)
    }

    func test_emailMatch_differentEmail_returnsNil() async {
        let bob = CustomerSummary.stub(id: 2, email: "bob@example.com", phone: nil)
        let api = ListCustomersStubAPI(response: [bob])
        let checker = CustomerDuplicateChecker(api: api)

        let result = await checker.findDuplicate(phone: "", email: "carol@example.com")

        XCTAssertNil(result)
    }

    // MARK: findDuplicate — phone match

    func test_phoneMatch_last10Digits_returnsCandidate() async {
        let dave = CustomerSummary.stub(id: 3, email: nil, phone: "+1-555-123-4567")
        let api = ListCustomersStubAPI(response: [dave])
        let checker = CustomerDuplicateChecker(api: api)

        // Search with just digits, same last-10
        let result = await checker.findDuplicate(phone: "5551234567", email: "")

        XCTAssertEqual(result?.id, 3)
    }

    func test_phoneMatch_differentLast10_returnsNil() async {
        let eve = CustomerSummary.stub(id: 4, email: nil, phone: "5559999999")
        let api = ListCustomersStubAPI(response: [eve])
        let checker = CustomerDuplicateChecker(api: api)

        let result = await checker.findDuplicate(phone: "5551234567", email: "")

        XCTAssertNil(result)
    }

    func test_phoneMatch_shortPhone_returnsNil() async {
        let api = ListCustomersStubAPI(response: [])
        let checker = CustomerDuplicateChecker(api: api)

        // Fewer than 7 digits → no search
        let result = await checker.findDuplicate(phone: "123", email: "")

        XCTAssertNil(result)
    }

    func test_bothEmpty_returnsNil() async {
        let api = ListCustomersStubAPI(response: [])
        let checker = CustomerDuplicateChecker(api: api)

        let result = await checker.findDuplicate(phone: "", email: "")

        XCTAssertNil(result)
    }

    // MARK: CustomerDuplicateCheckViewModel

    func test_viewModel_check_foundSetsFoundState() async {
        let alice = CustomerSummary.stub(id: 1, email: "alice@example.com", phone: nil)
        let api = ListCustomersStubAPI(response: [alice])
        let vm = CustomerDuplicateCheckViewModel(api: api)

        let found = await vm.check(phone: "", email: "alice@example.com")

        XCTAssertTrue(found)
        if case .found(let candidate) = vm.checkState {
            XCTAssertEqual(candidate.id, 1)
        } else {
            XCTFail("Expected .found, got \(vm.checkState)")
        }
    }

    func test_viewModel_check_notFoundSetsClearState() async {
        let api = ListCustomersStubAPI(response: [])
        let vm = CustomerDuplicateCheckViewModel(api: api)

        let found = await vm.check(phone: "", email: "nobody@example.com")

        XCTAssertFalse(found)
        if case .clear = vm.checkState {} else {
            XCTFail("Expected .clear, got \(vm.checkState)")
        }
    }

    func test_viewModel_dismiss_setsIdle() async {
        let api = ListCustomersStubAPI(response: [])
        let vm = CustomerDuplicateCheckViewModel(api: api)
        _ = await vm.check(phone: "", email: "")
        vm.dismiss()
        if case .idle = vm.checkState {} else {
            XCTFail("Expected .idle after dismiss, got \(vm.checkState)")
        }
    }

    func test_viewModel_initialState_isIdle() {
        let api = ListCustomersStubAPI(response: [])
        let vm = CustomerDuplicateCheckViewModel(api: api)
        if case .idle = vm.checkState {} else {
            XCTFail("Expected initial state to be .idle")
        }
    }
}

// MARK: - Helpers

private extension CustomerSummary {
    static func stub(id: Int64, email: String?, phone: String?) -> CustomerSummary {
        let json = """
        {"id":\(id),"first_name":"Test","last_name":"User",
         "email":\(email.flatMap { "\"\($0)\"" } ?? "null"),
         "phone":\(phone.flatMap { "\"\($0)\"" } ?? "null"),
         "mobile":null,"organization":null,"city":null,"state":null,
         "customer_group_name":null,"created_at":null,"ticket_count":null}
        """.data(using: .utf8)!
        return try! JSONDecoder().decode(CustomerSummary.self, from: json)
    }
}

// MARK: - Stub

private actor ListCustomersStubAPI: APIClient {
    private let response: [CustomerSummary]
    init(response: [CustomerSummary]) { self.response = response }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasPrefix("/api/v1/customers") {
            let list = CustomersListResponse(customers: response, pagination: nil)
            guard let cast = list as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
