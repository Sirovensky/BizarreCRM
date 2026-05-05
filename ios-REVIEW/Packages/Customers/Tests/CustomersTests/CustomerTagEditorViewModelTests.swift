import XCTest
@testable import Customers
import Networking

// §5.9 — CustomerTagEditorViewModel unit tests.

@MainActor
final class CustomerTagEditorViewModelTests: XCTestCase {

    private func makeDetail(tags: String?) -> CustomerDetail {
        let tagsJSON = tags.map { "\"\($0)\"" } ?? "null"
        let json = """
        {
          "id": 5,
          "first_name": "Eve",
          "last_name": null,
          "email": null,
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
          "customer_tags": \(tagsJSON),
          "comments": null,
          "created_at": "2026-01-01",
          "updated_at": "2026-01-01",
          "phones": [],
          "emails": []
        }
        """
        return try! JSONDecoder().decode(CustomerDetail.self, from: Data(json.utf8))
    }

    // MARK: - Tests

    func test_init_loadsInitialTags() {
        let detail = makeDetail(tags: "vip,gold,loyal")
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: detail.tagList)
        XCTAssertEqual(vm.selectedTags, ["vip", "gold", "loyal"])
    }

    func test_toggleTag_addsNewTag() {
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: [])
        vm.toggleTag("newTag")
        XCTAssertEqual(vm.selectedTags, ["newTag"])
    }

    func test_toggleTag_removesExistingTag() {
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: ["vip"])
        vm.toggleTag("vip")
        XCTAssertTrue(vm.selectedTags.isEmpty)
    }

    func test_toggleTag_ignoresEmptyString() {
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: [])
        vm.toggleTag("   ")
        XCTAssertTrue(vm.selectedTags.isEmpty)
    }

    func test_toggleTag_enforcesMax20Limit() {
        let initial = (1...20).map { "tag\($0)" }
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: initial)
        vm.toggleTag("overflow")
        // Still 20 — overflow rejected
        XCTAssertEqual(vm.selectedTags.count, 20)
        XCTAssertFalse(vm.selectedTags.contains("overflow"))
    }

    func test_removeTag_removesFromSelected() {
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: ["vip", "gold"])
        vm.removeTag("vip")
        XCTAssertEqual(vm.selectedTags, ["gold"])
    }

    func test_addQueryAsTag_addsAndClearsQuery() {
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: [])
        vm.query = "new-tag"
        vm.addQueryAsTag()
        XCTAssertTrue(vm.selectedTags.contains("new-tag"))
        XCTAssertTrue(vm.query.isEmpty)
    }

    func test_save_happyPath_setsSavedSuccessfully() async {
        let detail = makeDetail(tags: "vip")
        let stub = TagStubAPIClient(saveResult: .success(detail))
        let vm = CustomerTagEditorViewModel(api: stub, customerId: 5, initialTags: detail.tagList)

        await vm.save()

        XCTAssertTrue(vm.savedSuccessfully)
        XCTAssertNil(vm.saveError)
    }

    func test_save_serverError_setsSaveError() async {
        let stub = TagStubAPIClient(saveResult: .failure(APITransportError.httpStatus(422, message: "Invalid tag")))
        let vm = CustomerTagEditorViewModel(api: stub, customerId: 5, initialTags: [])

        await vm.save()

        XCTAssertFalse(vm.savedSuccessfully)
        XCTAssertNotNil(vm.saveError)
    }

    func test_immutability_toggleDoesNotMutateOriginalArray() {
        let original = ["vip", "gold"]
        let vm = CustomerTagEditorViewModel(api: TagStubAPIClient(), customerId: 5, initialTags: original)
        vm.toggleTag("newTag")
        // original array should be unchanged
        XCTAssertEqual(original, ["vip", "gold"])
        XCTAssertEqual(vm.selectedTags.count, 3)
    }
}

// MARK: - TagStubAPIClient

actor TagStubAPIClient: APIClient {
    let saveResult: Result<CustomerDetail, Error>?

    init(saveResult: Result<CustomerDetail, Error>? = nil) {
        self.saveResult = saveResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path == "/api/v1/customers/tags" {
            let json = #"{"tags":["suggested","premium"]}"#
            let decoded = try JSONDecoder().decode(TagSuggestionsResponse.self, from: Data(json.utf8))
            guard let cast = decoded as? T else { throw APITransportError.decoding("type mismatch") }
            return cast
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/tags"), let saveResult {
            switch saveResult {
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
