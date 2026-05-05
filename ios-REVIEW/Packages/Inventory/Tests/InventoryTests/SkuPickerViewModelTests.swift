import XCTest
@testable import Inventory
import Networking

@MainActor
final class SkuPickerViewModelTests: XCTestCase {

    func test_initialState_empty() {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: []))
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertFalse(vm.isSearching)
    }

    func test_clearSearch_resetsText() {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: []))
        vm.searchText = "something"
        vm.clearSearch()
        XCTAssertTrue(vm.searchText.isEmpty)
        XCTAssertTrue(vm.results.isEmpty)
    }

    func test_selectResult_addsToRecents() async {
        let stub = SkuStubAPIClient(results: [
            SkuSearchResult(id: 1, sku: "ABC-1", name: "Widget")
        ])
        let vm = SkuPickerViewModel(api: stub)
        let result = SkuSearchResult(id: 7, sku: "TEST-7", name: "Tester")
        vm.select(result)
        XCTAssertEqual(vm.recentSkus.first?.sku, "TEST-7")
    }

    func test_selectResult_deduplicatesRecent() {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: []))
        let result = SkuSearchResult(id: 5, sku: "DUP-5", name: "Dup")
        vm.select(result)
        vm.select(result)
        // Should appear only once
        let count = vm.recentSkus.filter { $0.id == 5 }.count
        XCTAssertEqual(count, 1)
    }

    func test_selectResult_mostRecentFirst() {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: []))
        let r1 = SkuSearchResult(id: 1, sku: "A", name: "A")
        let r2 = SkuSearchResult(id: 2, sku: "B", name: "B")
        vm.select(r1)
        vm.select(r2)
        XCTAssertEqual(vm.recentSkus[0].sku, "B")
        XCTAssertEqual(vm.recentSkus[1].sku, "A")
    }

    func test_recents_cappedAt10() {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: []))
        for i in 0..<15 {
            vm.select(SkuSearchResult(id: Int64(i), sku: "S\(i)", name: "Item \(i)"))
        }
        XCTAssertLessThanOrEqual(vm.recentSkus.count, 10)
    }

    // Debounce search: setting text to non-empty triggers search after 300ms.
    // We can't wait 300ms in tests so we call performSearch via the internal route.
    func test_searchResults_fromAPI() async {
        let expectedResults = [
            SkuSearchResult(id: 1, sku: "WDG-001", name: "Widget"),
            SkuSearchResult(id: 2, sku: "WDG-002", name: "Widget Pro")
        ]
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: expectedResults))
        await vm._performSearchForTesting(query: "WDG")
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertEqual(vm.results[0].sku, "WDG-001")
    }

    func test_searchResults_clearedOnEmptyQuery() async {
        let vm = SkuPickerViewModel(api: SkuStubAPIClient(results: [
            SkuSearchResult(id: 1, sku: "A", name: "A")
        ]))
        await vm._performSearchForTesting(query: "A")
        XCTAssertFalse(vm.results.isEmpty)
        vm.clearSearch()
        XCTAssertTrue(vm.results.isEmpty)
    }
}

// MARK: - Stubs & test helpers

actor SkuStubAPIClient: APIClient {
    let results: [SkuSearchResult]

    init(results: [SkuSearchResult]) { self.results = results }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        // Build a JSON payload and decode it into InventoryListResponse
        let itemsJSON = results.map { r -> String in
            """
            {"id": \(r.id), "sku": "\(r.sku)", "name": "\(r.name ?? "")",
             "item_type": "product", "upc_code": null, "in_stock": \(r.inStock ?? 0),
             "reorder_level": 1, "cost_price": null, "retail_price": \(r.retailPrice ?? 0),
             "manufacturer_name": null, "device_name": null, "supplier_name": null, "is_serialized": 0}
            """
        }.joined(separator: ",")
        let json = "{\"items\": [\(itemsJSON)], \"pagination\": null}"
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let data = Data(json.utf8)
        return try decoder.decode(T.self, from: data)
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

// Expose internal search method for tests so we don't need a 300ms sleep.
extension SkuPickerViewModel {
    func _performSearchForTesting(query: String) async {
        await _performSearch(query: query)
    }
}

// InventoryListItem test stub factory
extension InventoryListItem {
    static func stub(id: Int64, sku: String, name: String) -> InventoryListItem {
        // Decode from JSON to bypass memberwise init restrictions on the struct
        let json = """
        {"id": \(id), "sku": "\(sku)", "name": "\(name)", "item_type": "product",
         "upc_code": null, "in_stock": 5, "reorder_level": 2,
         "cost_price": null, "retail_price": 9.99,
         "manufacturer_name": null, "device_name": null,
         "supplier_name": null, "is_serialized": 0}
        """
        return try! JSONDecoder().decode(InventoryListItem.self, from: Data(json.utf8))
    }
}
