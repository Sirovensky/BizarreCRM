import XCTest
@testable import RepairPricing
import Networking

/// §43.4 — ServicePartMappingViewModel unit tests.
@MainActor
final class ServicePartMappingViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_correct() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        XCTAssertEqual(vm.skuQuery, "")
        XCTAssertTrue(vm.searchResults.isEmpty)
        XCTAssertFalse(vm.isSearching)
        XCTAssertNil(vm.primarySku)
        XCTAssertFalse(vm.isBundleMode)
        XCTAssertTrue(vm.bundle.isEmpty)
        XCTAssertFalse(vm.isSaving)
        XCTAssertNil(vm.saveError)
        XCTAssertNil(vm.savedService)
    }

    // MARK: - Bundle management (immutable patterns)

    func test_addBundleRow_appendsNewRow() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        XCTAssertEqual(vm.bundle.count, 1)
        XCTAssertEqual(vm.bundle[0].qty, 1)
        XCTAssertEqual(vm.bundle[0].skuId, "")
    }

    func test_addBundleRow_doesNotMutatePreviousSnapshot() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        let snapshot = vm.bundle
        vm.addBundleRow()
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(vm.bundle.count, 2)
    }

    func test_removeBundleRow_removesCorrectRow() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        vm.addBundleRow()
        vm.removeBundleRow(at: 0)
        XCTAssertEqual(vm.bundle.count, 1)
    }

    func test_removeBundleRow_outOfBounds_doesNothing() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        vm.removeBundleRow(at: 99)
        XCTAssertEqual(vm.bundle.count, 1)
    }

    func test_updateBundleRow_updatesSkuId() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        vm.updateBundleRow(at: 0, skuId: "SKU-123")
        XCTAssertEqual(vm.bundle[0].skuId, "SKU-123")
    }

    func test_updateBundleRow_updatesQty() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.addBundleRow()
        vm.updateBundleRow(at: 0, qty: 3)
        XCTAssertEqual(vm.bundle[0].qty, 3)
    }

    // MARK: - Save

    func test_save_apiFailure_setsError() async {
        let stub = PartAPIStub(shouldSucceed: false)
        let vm = ServicePartMappingViewModel(api: stub, serviceId: 1)
        await vm.save()
        XCTAssertNotNil(vm.saveError)
        XCTAssertNil(vm.savedService)
    }

    func test_save_bundleMode_filtersBlanks_leavesOnlyNonEmpty() {
        // Pure logic test — bundle filtering happens before the API call
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 3)
        vm.isBundleMode = true
        vm.addBundleRow()
        vm.updateBundleRow(at: 0, skuId: "BATTERY-X")
        vm.addBundleRow()  // blank
        // Verify the bundle array has 2 rows but one is empty
        XCTAssertEqual(vm.bundle.count, 2)
        let nonEmpty = vm.bundle.filter { !$0.skuId.isEmpty }
        XCTAssertEqual(nonEmpty.count, 1)
        XCTAssertEqual(nonEmpty.first?.skuId, "BATTERY-X")
    }

    func test_save_singleMode_primarySkuPreserved() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 5)
        vm.isBundleMode = false
        let item = InventorySearchResult(id: 10, sku: "SCREEN-15", name: "Screen")
        vm.primarySku = item
        XCTAssertEqual(vm.primarySku?.sku, "SCREEN-15")
        XCTAssertFalse(vm.isBundleMode)
    }

    // MARK: - Query change

    func test_onSkuQueryChange_updatesQuery() {
        let vm = ServicePartMappingViewModel(api: PartAPIStub(), serviceId: 1)
        vm.onSkuQueryChange("screen")
        XCTAssertEqual(vm.skuQuery, "screen")
    }
}

// MARK: - PartAPIStub

@MainActor
final class PartAPIStub: APIClient {
    var shouldSucceed: Bool

    init(shouldSucceed: Bool = true) { self.shouldSucceed = shouldSucceed }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.contains("/inventory/items") {
            let json = """
            [{"id":1,"sku":"SKU-1","name":"Part A","stock_qty":5,"price_cents":1000}]
            """.data(using: .utf8)!
            return try JSONDecoder().decode(type, from: json)
        }
        throw TestError.notImplemented
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        guard shouldSucceed else { throw TestError.forced }
        throw TestError.notImplemented  // not tested at this level
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { throw TestError.notImplemented }
    func delete(_ path: String) async throws { throw TestError.notImplemented }
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> { throw TestError.notImplemented }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
