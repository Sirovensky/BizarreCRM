import XCTest
@testable import Inventory
import Networking

// MARK: - Minimal stub for adjustment tests

/// Self-contained stub that supports adjustStock and listLowStock alongside
/// the create/update stubs needed by existing actors. Mirrors the pattern
/// in `StubAPIClient.swift` but adds the new endpoints.
actor AdjustStubAPIClient: APIClient {
    private let adjustResult: Result<AdjustStockResponse, Error>?
    private let lowStockResult: Result<[LowStockItem], Error>?
    private let createResult: Result<CreatedResource, Error>?

    init(
        adjustResult: Result<AdjustStockResponse, Error>? = nil,
        lowStockResult: Result<[LowStockItem], Error>? = nil,
        createResult: Result<CreatedResource, Error>? = nil
    ) {
        self.adjustResult = adjustResult
        self.lowStockResult = lowStockResult
        self.createResult = createResult
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if path.hasSuffix("/low-stock"), let result = lowStockResult {
            switch result {
            case .success(let items):
                guard let cast = items as? T else { throw APITransportError.decoding("type mismatch in get") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if path.hasSuffix("/adjust-stock"), let result = adjustResult {
            switch result {
            case .success(let r):
                guard let cast = r as? T else { throw APITransportError.decoding("type mismatch in post") }
                return cast
            case .failure(let err):
                throw err
            }
        }
        if path.hasPrefix("/api/v1/inventory"), let result = createResult {
            switch result {
            case .success(let created):
                guard let cast = created as? T else { throw APITransportError.decoding("type mismatch") }
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

// MARK: - InventoryAdjustmentTests

@MainActor
final class InventoryAdjustmentTests: XCTestCase {

    // MARK: 1. AdjustStockRequest snake_case encoding

    func test_adjustStockRequest_encodes_quantityKey() throws {
        let req = AdjustStockRequest(deltaQty: 5, reason: "recount", notes: "shelf audit")
        let encoder = JSONEncoder()
        let data = try encoder.encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        // deltaQty → "quantity" per server contract
        XCTAssertEqual(json["quantity"] as? Int, 5)
        // reason → "type" per server contract
        XCTAssertEqual(json["type"] as? String, "recount")
        XCTAssertEqual(json["notes"] as? String, "shelf audit")
        // camelCase keys must NOT appear
        XCTAssertNil(json["deltaQty"])
        XCTAssertNil(json["reason"])
    }

    func test_adjustStockRequest_negative_delta_encodes() throws {
        let req = AdjustStockRequest(deltaQty: -3, reason: "shrinkage", notes: nil)
        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["quantity"] as? Int, -3)
        XCTAssertEqual(json["type"] as? String, "shrinkage")
        XCTAssertNil(json["notes"])
    }

    func test_adjustStockRequest_large_positive_encodes() throws {
        let req = AdjustStockRequest(deltaQty: 1_000_000, reason: "receive")
        let data = try JSONEncoder().encode(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["quantity"] as? Int, 1_000_000)
    }

    // MARK: 2. LowStockItem snake_case decoding

    func test_lowStockItem_decodes_fields() throws {
        let json = """
        {
            "id": 42,
            "name": "iPhone 15 Screen",
            "sku": "SCR-IP15",
            "in_stock": 2,
            "reorder_level": 10
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder().decode(LowStockItem.self, from: json)

        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.name, "iPhone 15 Screen")
        XCTAssertEqual(item.sku, "SCR-IP15")
        XCTAssertEqual(item.currentQty, 2)
        XCTAssertEqual(item.reorderThreshold, 10)
        XCTAssertEqual(item.shortageBy, 8)   // 10 - 2
    }

    func test_lowStockItem_shortageBy_is_zero_at_threshold() throws {
        let json = """
        { "id": 1, "name": "Widget", "sku": null, "in_stock": 10, "reorder_level": 10 }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(LowStockItem.self, from: json)
        XCTAssertEqual(item.shortageBy, 0)
    }

    func test_lowStockItem_missing_sku_is_nil() throws {
        let json = """
        { "id": 99, "name": "Part", "in_stock": 1, "reorder_level": 5 }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(LowStockItem.self, from: json)
        XCTAssertNil(item.sku)
    }

    func test_lowStockItem_missing_name_falls_back() throws {
        let json = """
        { "id": 7, "in_stock": 0, "reorder_level": 3 }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(LowStockItem.self, from: json)
        XCTAssertEqual(item.name, "Unnamed")
    }

    func test_lowStockItem_identifies_by_id() throws {
        let json = """
        { "id": 55, "name": "Cap", "in_stock": 3, "reorder_level": 8 }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(LowStockItem.self, from: json)
        XCTAssertEqual(item.id, 55)
    }

    // MARK: 3. InventoryAdjustViewModel.validateDelta() — pure validators

    func test_validateDelta_zero_is_invalid() {
        let vm = makeVM()
        XCTAssertFalse(vm.validateDelta(0))
    }

    func test_validateDelta_positive_one_is_valid() {
        let vm = makeVM()
        XCTAssertTrue(vm.validateDelta(1))
    }

    func test_validateDelta_negative_one_is_valid() {
        let vm = makeVM()
        XCTAssertTrue(vm.validateDelta(-1))
    }

    func test_validateDelta_boundary_max_is_valid() {
        let vm = makeVM()
        XCTAssertTrue(vm.validateDelta(1_000_000))
        XCTAssertTrue(vm.validateDelta(-1_000_000))
    }

    func test_validateDelta_over_boundary_is_invalid() {
        let vm = makeVM()
        XCTAssertFalse(vm.validateDelta(1_000_001))
        XCTAssertFalse(vm.validateDelta(-1_000_001))
    }

    // isValid property mirrors validateDelta(delta)
    func test_isValid_reflects_delta_state() {
        let vm = makeVM()
        XCTAssertFalse(vm.isValid)   // delta == 0 at init
        vm.delta = 5
        XCTAssertTrue(vm.isValid)
        vm.delta = 0
        XCTAssertFalse(vm.isValid)
    }

    // MARK: 4. InventoryAdjustViewModel async submit

    func test_submit_success_sets_newQty() async {
        let stub = AdjustStubAPIClient(
            adjustResult: .success(AdjustStockResponse(newQty: 15, auditId: 99))
        )
        let vm = InventoryAdjustViewModel(itemId: 42, itemName: "Part", api: stub)
        vm.delta = 5
        vm.reason = .receive

        await vm.submit()

        XCTAssertEqual(vm.newQty, 15)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isSubmitting)
    }

    func test_submit_zero_delta_is_noop() async {
        let stub = AdjustStubAPIClient(
            adjustResult: .success(AdjustStockResponse(newQty: 10, auditId: 1))
        )
        let vm = InventoryAdjustViewModel(itemId: 1, itemName: "X", api: stub)
        vm.delta = 0  // guard fails → no network call

        await vm.submit()

        XCTAssertNil(vm.newQty)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_server_error_sets_errorMessage() async {
        let stub = AdjustStubAPIClient(
            adjustResult: .failure(APITransportError.httpStatus(400, message: "Insufficient stock"))
        )
        let vm = InventoryAdjustViewModel(itemId: 1, itemName: "X", api: stub)
        vm.delta = -50

        await vm.submit()

        XCTAssertNil(vm.newQty)
        XCTAssertEqual(vm.errorMessage, "Insufficient stock")
    }

    // MARK: - Helpers

    private func makeVM(delta: Int = 0) -> InventoryAdjustViewModel {
        InventoryAdjustViewModel(
            itemId: 1,
            itemName: "Test Item",
            api: AdjustStubAPIClient()
        )
    }
}
