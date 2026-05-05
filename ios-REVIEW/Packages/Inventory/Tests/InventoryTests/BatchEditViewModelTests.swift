import XCTest
@testable import Inventory
import Networking

@MainActor
final class BatchEditViewModelTests: XCTestCase {

    func test_hasAnyField_false_whenAllEmpty() {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1, 2])
        XCTAssertFalse(vm.hasAnyField)
    }

    func test_hasAnyField_true_withPriceAdjust() {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1])
        vm.priceAdjustPercent = "10"
        XCTAssertTrue(vm.hasAnyField)
    }

    func test_hasAnyField_true_withCategory() {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1])
        vm.reassignCategory = "Cables"
        XCTAssertTrue(vm.hasAnyField)
    }

    func test_hasAnyField_true_withTags() {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1])
        vm.newTags = "sale, clearance"
        XCTAssertTrue(vm.hasAnyField)
    }

    func test_submit_setsErrorWhenNoFields() async {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1])
        await vm.submit()
        XCTAssertEqual(vm.errorMessage, "Enter at least one update.")
        XCTAssertNil(vm.result)
    }

    func test_submit_setsResultOnSuccess() async {
        let stub = BatchStubAPIClient(updatedCount: 3)
        let vm = BatchEditViewModel(api: stub, selectedIds: [1, 2, 3])
        vm.priceAdjustPercent = "5"
        await vm.submit()
        XCTAssertEqual(vm.result, 3)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_setsErrorOnServerFailure() async {
        let stub = BatchStubAPIClient(shouldFail: true)
        let vm = BatchEditViewModel(api: stub, selectedIds: [1])
        vm.reassignCategory = "Parts"
        await vm.submit()
        XCTAssertNil(vm.result)
        XCTAssertNotNil(vm.errorMessage)
    }

    func test_submit_emptyIds_doesNothing() async {
        let stub = BatchStubAPIClient(updatedCount: 0)
        let vm = BatchEditViewModel(api: stub, selectedIds: [])
        vm.priceAdjustPercent = "10"
        await vm.submit()
        XCTAssertNil(vm.result)
    }

    func test_whitespaceOnlyFields_notHasAnyField() {
        let vm = BatchEditViewModel(api: StubAPIClient(), selectedIds: [1])
        vm.priceAdjustPercent = "   "
        vm.reassignCategory = "\t"
        vm.newTags = "  "
        XCTAssertFalse(vm.hasAnyField)
    }
}

// MARK: - Stubs

actor BatchStubAPIClient: APIClient {
    let updatedCount: Int
    let shouldFail: Bool

    init(updatedCount: Int = 0, shouldFail: Bool = false) {
        self.updatedCount = updatedCount
        self.shouldFail = shouldFail
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldFail { throw APITransportError.httpStatus(500, message: "Server error") }
        let resp = BatchInventoryResponse(updatedCount: updatedCount)
        guard let cast = resp as? T else { throw APITransportError.decoding("type mismatch") }
        return cast
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw APITransportError.noBaseURL }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw APITransportError.noBaseURL }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
