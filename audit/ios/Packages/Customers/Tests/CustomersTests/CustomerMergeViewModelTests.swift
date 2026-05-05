import XCTest
@testable import Customers
import Networking

// §5.5 — CustomerMergeViewModel unit tests.

@MainActor
final class CustomerMergeViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makePrimary(id: Int64 = 1) -> CustomerDetail {
        let json = """
        {
          "id": \(id),
          "first_name": "Alice",
          "last_name": "Primary",
          "email": "alice@example.com",
          "phone": "5551111111",
          "mobile": null,
          "address1": "1 Main St",
          "city": "Springfield",
          "state": "IL",
          "country": null,
          "postcode": "62701",
          "organization": null,
          "contact_person": null,
          "customer_group_name": null,
          "customer_tags": "vip,gold",
          "comments": "Primary notes",
          "created_at": "2026-01-01",
          "updated_at": "2026-01-01",
          "phones": [],
          "emails": []
        }
        """
        return try! JSONDecoder().decode(CustomerDetail.self, from: Data(json.utf8))
    }

    private func makeSecondary(id: Int64 = 2) -> CustomerSummary {
        let json = """
        {
          "id": \(id),
          "first_name": "Bob",
          "last_name": "Secondary",
          "email": "bob@example.com",
          "phone": "5552222222",
          "mobile": null,
          "organization": null,
          "city": "Chicago",
          "state": "IL",
          "customer_group_name": null,
          "created_at": "2026-01-02",
          "ticket_count": 0
        }
        """
        return try! JSONDecoder().decode(CustomerSummary.self, from: Data(json.utf8))
    }

    // MARK: - Tests

    func test_init_setsCorrectPrimary() {
        let primary = makePrimary()
        let stub = MergeStubAPIClient()
        let vm = CustomerMergeViewModel(api: stub, primary: primary)
        XCTAssertEqual(vm.primary.id, 1)
        XCTAssertFalse(vm.mergeComplete)
    }

    func test_selectCandidate_buildsFieldRows() async {
        let primary = makePrimary()
        let secondary = makeSecondary()
        let stub = MergeStubAPIClient()
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)

        XCTAssertEqual(vm.selectedCandidate?.id, 2)
        XCTAssertEqual(vm.fieldRows.count, 5)
        XCTAssertTrue(vm.fieldRows.allSatisfy { $0.winner == .primary })
    }

    func test_setWinner_updatesRow() async {
        let vm = CustomerMergeViewModel(api: MergeStubAPIClient(), primary: makePrimary())
        await vm.selectCandidate(makeSecondary())

        vm.setWinner(.secondary, forRowId: "email")

        let emailRow = vm.fieldRows.first(where: { $0.id == "email" })
        XCTAssertEqual(emailRow?.winner, .secondary)
    }

    func test_performMerge_successMarksMergeComplete() async {
        let primary = makePrimary()
        let secondary = makeSecondary()
        let stub = MergeStubAPIClient(mergeResult: .success(primary))
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)
        await vm.performMerge()

        XCTAssertTrue(vm.mergeComplete)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.conflictMessage)
    }

    func test_performMerge_conflictSetsConflictMessage() async {
        let primary = makePrimary()
        let secondary = makeSecondary()
        let stub = MergeStubAPIClient(
            mergeResult: .failure(APITransportError.httpStatus(409, message: "customer has open ticket — resolve first"))
        )
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)
        await vm.performMerge()

        XCTAssertFalse(vm.mergeComplete)
        XCTAssertNotNil(vm.conflictMessage)
        XCTAssertNil(vm.errorMessage)
    }

    func test_performMerge_serverErrorSetsErrorMessage() async {
        let primary = makePrimary()
        let secondary = makeSecondary()
        let stub = MergeStubAPIClient(
            mergeResult: .failure(APITransportError.httpStatus(500, message: "Internal error"))
        )
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)
        await vm.performMerge()

        XCTAssertFalse(vm.mergeComplete)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.conflictMessage)
    }

    func test_performMerge_withNoCandidate_doesNothing() async {
        let stub = MergeStubAPIClient(mergeResult: .success(makePrimary()))
        let vm = CustomerMergeViewModel(api: stub, primary: makePrimary())
        // No selectCandidate call → guard fires
        await vm.performMerge()
        XCTAssertFalse(vm.mergeComplete)
    }

    func test_performMerge_sendsCorrectKeepAndMergeIds() async throws {
        // Verify the stub sees keep_id = primary.id and merge_id = secondary.id.
        let primary = makePrimary(id: 10)
        let secondary = makeSecondary(id: 20)
        let stub = MergeStubAPIClient(mergeResult: .success(primary), captureRequest: true)
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)
        await vm.performMerge()

        XCTAssertTrue(vm.mergeComplete)
        let captured = await stub.capturedMergeRequest
        XCTAssertEqual(captured?.keepId, 10)
        XCTAssertEqual(captured?.mergeId, 20)
    }

    func test_performMerge_fieldPreferencesDoNotAffectApiCall() async {
        // Field prefs are local-only; changing them must not change the API body
        // (there is no field_preferences key in the server body).
        let primary = makePrimary()
        let secondary = makeSecondary()
        let stub = MergeStubAPIClient(mergeResult: .success(primary), captureRequest: true)
        let vm = CustomerMergeViewModel(api: stub, primary: primary)

        await vm.selectCandidate(secondary)
        vm.setWinner(.secondary, forRowId: "email")
        vm.setWinner(.secondary, forRowId: "name")
        await vm.performMerge()

        XCTAssertTrue(vm.mergeComplete)
        // API must still receive exactly keep_id/merge_id; no field_preferences.
        let captured = await stub.capturedMergeRequest
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.keepId, primary.id)
        XCTAssertEqual(captured?.mergeId, secondary.id)
    }

    func test_searchCandidates_excludesPrimary() async {
        let primary = makePrimary(id: 1)
        let stub = MergeStubAPIClient(listResult: .success([makeSecondary(id: 1), makeSecondary(id: 2)]))
        let vm = CustomerMergeViewModel(api: stub, primary: primary)
        vm.candidateQuery = "Bob"

        await vm.searchCandidates()

        // id=1 is the primary; must be filtered out
        XCTAssertTrue(vm.candidateResults.allSatisfy { $0.id != 1 })
        XCTAssertEqual(vm.candidateResults.count, 1)
    }

    func test_searchCandidates_shortQueryClearsResults() async {
        let stub = MergeStubAPIClient()
        let vm = CustomerMergeViewModel(api: stub, primary: makePrimary())
        vm.candidateQuery = "B"   // 1 char — below threshold

        await vm.searchCandidates()

        XCTAssertTrue(vm.candidateResults.isEmpty)
    }

    func test_fieldRows_defaultWinnerIsPrimary() async {
        let vm = CustomerMergeViewModel(api: MergeStubAPIClient(), primary: makePrimary())
        await vm.selectCandidate(makeSecondary())
        XCTAssertTrue(vm.fieldRows.allSatisfy { $0.winner == .primary })
    }

    func test_fieldRows_winnerValueReflectsSelection() async {
        let vm = CustomerMergeViewModel(api: MergeStubAPIClient(), primary: makePrimary())
        await vm.selectCandidate(makeSecondary())

        vm.setWinner(.secondary, forRowId: "email")
        let row = vm.fieldRows.first(where: { $0.id == "email" })!
        XCTAssertEqual(row.winnerValue, row.secondaryValue)

        vm.setWinner(.primary, forRowId: "email")
        let row2 = vm.fieldRows.first(where: { $0.id == "email" })!
        XCTAssertEqual(row2.winnerValue, row2.primaryValue)
    }
}

// MARK: - MergeStubAPIClient

/// Extended stub supporting merge + list endpoints.
/// Set `captureRequest: true` to record the `CustomerMergeRequest` for assertion.
actor MergeStubAPIClient: APIClient {
    let mergeResult: Result<CustomerDetail, Error>?
    let listResult: Result<[CustomerSummary], Error>?
    let shouldCapture: Bool
    private(set) var capturedMergeRequest: CustomerMergeRequest?

    init(
        mergeResult: Result<CustomerDetail, Error>? = nil,
        listResult: Result<[CustomerSummary], Error>? = nil,
        captureRequest: Bool = false
    ) {
        self.mergeResult = mergeResult
        self.listResult = listResult
        self.shouldCapture = captureRequest
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/customers", let listResult {
            switch listResult {
            case .success(let summaries):
                let items = summaries.map { s -> String in
                    """
                    {"id":\(s.id),"first_name":"\(s.firstName ?? "")","last_name":"\(s.lastName ?? "")","email":null,"phone":null,"mobile":null,"organization":null,"city":null,"state":null,"customer_group_name":null,"created_at":null,"ticket_count":0}
                    """
                }.joined(separator: ",")
                let wrapper = "{\"customers\":[\(items)],\"pagination\":null}"
                let response = try JSONDecoder().decode(CustomersListResponse.self, from: Data(wrapper.utf8))
                guard let cast = response as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path == "/api/v1/customers/merge" {
            // Capture the request body for assertion tests.
            if shouldCapture, let req = body as? CustomerMergeRequest {
                capturedMergeRequest = req
            }
            guard let mergeResult else { throw APITransportError.noBaseURL }
            switch mergeResult {
            case .success(let detail):
                guard let cast = detail as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
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
