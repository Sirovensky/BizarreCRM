import XCTest
@testable import Inventory
import Networking

@MainActor
final class StocktakeStartViewModelTests: XCTestCase {

    func test_scopeDescription_noSelection_returnsAll() {
        let vm = StocktakeStartViewModel(api: StocktakeStubAPIClient())
        XCTAssertEqual(vm.scopeDescription, "All items")
    }

    func test_scopeDescription_withCategory() {
        let vm = StocktakeStartViewModel(api: StocktakeStubAPIClient())
        vm.selectedCategory = "Batteries"
        XCTAssertEqual(vm.scopeDescription, "Category: Batteries")
    }

    func test_scopeDescription_withLocation() {
        let vm = StocktakeStartViewModel(api: StocktakeStubAPIClient())
        vm.selectedLocation = "Shelf A"
        XCTAssertEqual(vm.scopeDescription, "Location: Shelf A")
    }

    func test_start_success_setsStartedSession() async {
        let stub = StocktakeStubAPIClient(session: StocktakeSession(id: 42, status: "open"))
        let vm = StocktakeStartViewModel(api: stub)
        await vm.start()
        XCTAssertEqual(vm.startedSession?.id, 42)
        XCTAssertNil(vm.errorMessage)
    }

    func test_start_offline_setsOfflineError() async {
        let stub = StocktakeStubAPIClient(shouldFailWithNetwork: true)
        let vm = StocktakeStartViewModel(api: stub)
        await vm.start()
        XCTAssertNil(vm.startedSession)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.errorMessage?.contains("offline") == true)
    }

    func test_start_serverError_setsErrorMessage() async {
        let stub = StocktakeStubAPIClient(serverError: "Stocktake already in progress")
        let vm = StocktakeStartViewModel(api: stub)
        await vm.start()
        XCTAssertNil(vm.startedSession)
        XCTAssertNotNil(vm.errorMessage)
    }
}

@MainActor
final class StocktakeScanViewModelTests: XCTestCase {

    func test_applyBarcode_knownSku_incrementsCount() {
        let vm = StocktakeScanViewModel(api: StocktakeStubAPIClient(), sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "PART-X", expectedQty: 10)
        ])
        vm._setSessionForTesting(session)

        let found = vm.applyBarcode("PART-X")
        XCTAssertTrue(found)
        XCTAssertEqual(vm.actualCounts["PART-X"], "1")

        vm.applyBarcode("PART-X")
        XCTAssertEqual(vm.actualCounts["PART-X"], "2")
    }

    func test_applyBarcode_unknownSku_returnsFalse() {
        let vm = StocktakeScanViewModel(api: StocktakeStubAPIClient(), sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "PART-X", expectedQty: 10)
        ])
        vm._setSessionForTesting(session)

        let found = vm.applyBarcode("MISSING-SKU")
        XCTAssertFalse(found)
    }

    func test_discrepancies_empty_whenAllExact() {
        let vm = StocktakeScanViewModel(api: StocktakeStubAPIClient(), sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "A", expectedQty: 5)
        ])
        vm._setSessionForTesting(session)
        vm.actualCounts["A"] = "5"
        XCTAssertTrue(vm.discrepancies.isEmpty)
    }

    func test_discrepancies_showsWhenActualDiffers() {
        let vm = StocktakeScanViewModel(api: StocktakeStubAPIClient(), sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "A", expectedQty: 5)
        ])
        vm._setSessionForTesting(session)
        vm.actualCounts["A"] = "3"
        XCTAssertEqual(vm.discrepancies.count, 1)
        XCTAssertEqual(vm.discrepancies[0].delta, -2)
    }

    func test_summary_countsProgress() {
        let vm = StocktakeScanViewModel(api: StocktakeStubAPIClient(), sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "A", expectedQty: 5),
            StocktakeRow(id: 2, sku: "B", expectedQty: 3)
        ])
        vm._setSessionForTesting(session)
        vm.actualCounts["A"] = "5"  // exact

        let s = vm.summary
        XCTAssertEqual(s.totalRows, 2)
        XCTAssertEqual(s.countedRows, 1)
        XCTAssertEqual(s.discrepancyCount, 0)
    }

    func test_finalize_success_setsShowReview() async {
        let stub = StocktakeStubAPIClient(session: StocktakeSession(id: 1, status: "open"))
        let vm = StocktakeScanViewModel(api: stub, sessionId: 1)
        let session = StocktakeSession(id: 1, status: "open", rows: [
            StocktakeRow(id: 1, sku: "A", expectedQty: 5)
        ])
        vm._setSessionForTesting(session)
        vm.actualCounts["A"] = "5"

        await vm.finalize()
        XCTAssertTrue(vm.showReview)
    }
}

// MARK: - Stub

actor StocktakeStubAPIClient: APIClient {
    let stubbedSession: StocktakeSession?
    let shouldFailWithNetwork: Bool
    let serverErrorMessage: String?

    init(session: StocktakeSession? = nil,
         shouldFailWithNetwork: Bool = false,
         serverError: String? = nil) {
        self.stubbedSession = session
        self.shouldFailWithNetwork = shouldFailWithNetwork
        self.serverErrorMessage = serverError
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if shouldFailWithNetwork { throw URLError(.notConnectedToInternet) }
        if let msg = serverErrorMessage { throw APITransportError.httpStatus(422, message: msg) }
        // stocktake start → returns StocktakeSession
        if let s = stubbedSession as? T { return s }
        // finalize → returns CreatedResource
        if let r = CreatedResource(id: 1) as? T { return r }
        throw APITransportError.decoding("type mismatch")
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
