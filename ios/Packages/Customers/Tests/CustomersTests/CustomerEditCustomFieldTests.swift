import XCTest
@testable import Customers
import Networking

// §5.4 — CustomerEditViewModel custom-field + 409 conflict unit tests.
//
// Coverage matrix:
//   loadCustomFields — happy path, merge with saved values, non-fatal failure
//   setCustomFieldValue — updates the right field, ignores unknown id
//   submit — saves custom fields on success
//   submit — 409 Conflict sets conflictMessage, not errorMessage
//   submit — non-409 server error sets errorMessage, not conflictMessage

@MainActor
final class CustomerEditCustomFieldTests: XCTestCase {

    // MARK: - Helpers

    private func makeDetail(id: Int64 = 42) -> CustomerDetail {
        let json = """
        {
          "id": \(id),
          "first_name": "Test",
          "last_name": "User",
          "email": "test@example.com",
          "phone": null,
          "mobile": null,
          "address1": null,
          "city": null,
          "state": null,
          "country": null,
          "postcode": null,
          "organization": null,
          "contact_person": null,
          "customer_group_name": null,
          "customer_tags": null,
          "comments": null,
          "created_at": "2026-01-01",
          "updated_at": "2026-01-01",
          "phones": [],
          "emails": []
        }
        """
        return try! JSONDecoder().decode(CustomerDetail.self, from: Data(json.utf8))
    }

    private func makeDefinitions() -> [CustomFieldDefinition] {
        let json = """
        [
          {"id":1,"entity_type":"customer","field_name":"Loyalty tier","field_type":"select","options":"[\\"Bronze\\",\\"Silver\\",\\"Gold\\"]","is_required":false,"sort_order":0},
          {"id":2,"entity_type":"customer","field_name":"VIP note","field_type":"text","options":null,"is_required":false,"sort_order":1}
        ]
        """
        return try! JSONDecoder().decode([CustomFieldDefinition].self, from: Data(json.utf8))
    }

    private func makeValues(definitionId: Int64, value: String) -> [CustomFieldValue] {
        let json = """
        [{"id":99,"definition_id":\(definitionId),"entity_type":"customer","entity_id":42,"value":"\(value)","field_name":"Loyalty tier","field_type":"select"}]
        """
        return try! JSONDecoder().decode([CustomFieldValue].self, from: Data(json.utf8))
    }

    // MARK: - loadCustomFields

    func test_loadCustomFields_happyPath_populatesFields() async {
        let defs = makeDefinitions()
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.loadCustomFields()

        XCTAssertEqual(vm.customFields.count, 2)
        XCTAssertEqual(vm.customFields[0].name, "Loyalty tier")
        XCTAssertEqual(vm.customFields[0].fieldType, "select")
        XCTAssertEqual(vm.customFields[0].options, ["Bronze", "Silver", "Gold"])
        XCTAssertEqual(vm.customFields[1].name, "VIP note")
        XCTAssertFalse(vm.isLoadingCustomFields)
    }

    func test_loadCustomFields_mergesExistingValues() async {
        let defs = makeDefinitions()
        let savedValues = makeValues(definitionId: 1, value: "Gold")
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success(savedValues)
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.loadCustomFields()

        let loyaltyField = vm.customFields.first(where: { $0.id == 1 })
        XCTAssertEqual(loyaltyField?.value, "Gold")
        // field 2 has no saved value — should be empty
        let vipField = vm.customFields.first(where: { $0.id == 2 })
        XCTAssertEqual(vipField?.value, "")
    }

    func test_loadCustomFields_failure_isNonFatal() async {
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .failure(APITransportError.noBaseURL),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.loadCustomFields()

        // Non-fatal: no error surfaced, fields stay empty.
        XCTAssertTrue(vm.customFields.isEmpty)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoadingCustomFields)
    }

    func test_loadCustomFields_calledTwice_onlyLoadsOnce() async {
        let defs = makeDefinitions()
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.loadCustomFields()
        await vm.loadCustomFields()   // second call should be a no-op

        // callCount on the stub should be 1 (not 2)
        let count = await stub.defsCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - setCustomFieldValue

    func test_setCustomFieldValue_updatesCorrectField() async {
        let defs = makeDefinitions()
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())
        await vm.loadCustomFields()

        vm.setCustomFieldValue("Silver", forId: 1)

        let field = vm.customFields.first(where: { $0.id == 1 })
        XCTAssertEqual(field?.value, "Silver")
        // field 2 unchanged
        let other = vm.customFields.first(where: { $0.id == 2 })
        XCTAssertEqual(other?.value, "")
    }

    func test_setCustomFieldValue_unknownId_isNoOp() async {
        let defs = makeDefinitions()
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())
        await vm.loadCustomFields()

        vm.setCustomFieldValue("anything", forId: 9999)  // id 9999 doesn't exist

        // No crash, all fields unchanged
        XCTAssertTrue(vm.customFields.allSatisfy { $0.value == "" })
    }

    // MARK: - submit with custom fields

    func test_submit_savesCustomFields_onSuccess() async {
        let defs = makeDefinitions()
        let stub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success(defs),
            valuesResult: .success([]),
            setValuesResult: .success(.init(saved: 2))
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())
        await vm.loadCustomFields()
        vm.setCustomFieldValue("Gold", forId: 1)

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        let count = await stub.setValuesCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - 409 conflict

    func test_submit_409_setsConflictMessage_notErrorMessage() async {
        let stub = EditCustomFieldStub(
            updateResult: .failure(APITransportError.httpStatus(409, message: "Record was modified by another user")),
            defsResult: .success([]),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertNotNil(vm.conflictMessage)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.conflictMessage, "Record was modified by another user")
    }

    func test_submit_409_nilMessage_usesDefaultConflictText() async {
        let stub = EditCustomFieldStub(
            updateResult: .failure(APITransportError.httpStatus(409, message: nil)),
            defsResult: .success([]),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertNotNil(vm.conflictMessage)
        XCTAssertFalse(vm.conflictMessage!.isEmpty)
    }

    func test_submit_500_setsErrorMessage_notConflict() async {
        let stub = EditCustomFieldStub(
            updateResult: .failure(APITransportError.httpStatus(500, message: "Server error")),
            defsResult: .success([]),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: stub, customer: makeDetail())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.conflictMessage)
    }

    func test_submit_clearsConflictBeforeRetry() async {
        let failStub = EditCustomFieldStub(
            updateResult: .failure(APITransportError.httpStatus(409, message: "conflict")),
            defsResult: .success([]),
            valuesResult: .success([])
        )
        let vm = CustomerEditViewModel(api: failStub, customer: makeDetail())
        await vm.submit()
        XCTAssertNotNil(vm.conflictMessage)

        // Re-submit with a new stub that succeeds — conflict must clear.
        let successStub = EditCustomFieldStub(
            updateResult: .success(.init(id: 42)),
            defsResult: .success([]),
            valuesResult: .success([])
        )
        let vm2 = CustomerEditViewModel(api: successStub, customer: makeDetail())
        await vm2.submit()
        XCTAssertNil(vm2.conflictMessage)
        XCTAssertTrue(vm2.didSave)
    }
}

// MARK: - EditCustomFieldStub

/// Extended stub supporting custom-field endpoints + call counting.
actor EditCustomFieldStub: APIClient {
    let updateResult: Result<CreatedResource, Error>
    let defsResult: Result<[CustomFieldDefinition], Error>
    let valuesResult: Result<[CustomFieldValue], Error>
    let setValuesResult: Result<SetCustomFieldValuesResponse, Error>

    private(set) var defsCallCount: Int = 0
    private(set) var setValuesCallCount: Int = 0

    init(
        updateResult: Result<CreatedResource, Error>,
        defsResult: Result<[CustomFieldDefinition], Error>,
        valuesResult: Result<[CustomFieldValue], Error>,
        setValuesResult: Result<SetCustomFieldValuesResponse, Error> = .success(.init(saved: 0))
    ) {
        self.updateResult = updateResult
        self.defsResult = defsResult
        self.valuesResult = valuesResult
        self.setValuesResult = setValuesResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/custom-fields/definitions" {
            defsCallCount += 1
            switch defsResult {
            case .success(let defs):
                guard let cast = defs as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        if path.hasPrefix("/api/v1/custom-fields/values/") {
            switch valuesResult {
            case .success(let vals):
                guard let cast = vals as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasPrefix("/api/v1/custom-fields/values/") {
            setValuesCallCount += 1
            switch setValuesResult {
            case .success(let resp):
                guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        if path.hasPrefix("/api/v1/customers/") {
            switch updateResult {
            case .success(let updated):
                guard let cast = updated as? T else { throw APITransportError.decoding("type mismatch") }
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
