import XCTest
@testable import Inventory
import Networking

@MainActor
final class InventoryEditViewModelTests: XCTestCase {

    private func sampleItem(id: Int64 = 42) -> InventoryItemDetail {
        // Decode from a minimal JSON — `InventoryItemDetail` is Decodable,
        // and defining a fixture via JSON insulates us from memberwise
        // initializer drift when new optional fields are added server-side.
        let json = #"""
        {
          "id": \#(id),
          "name": "Phone case",
          "item_type": "product",
          "description": "Tempered glass case, clear.",
          "sku": "CASE-001",
          "upc_code": "0123456789012",
          "in_stock": 12,
          "reorder_level": 5,
          "cost_price": 2.50,
          "retail_price": 19.99,
          "manufacturer_name": "Acme",
          "supplier_name": "Acme Distribution",
          "device_name": null,
          "image": null,
          "stock_warning": null,
          "is_serialized": 0,
          "created_at": "2026-04-20",
          "updated_at": "2026-04-20"
        }
        """#
        let decoder = JSONDecoder()
        return try! decoder.decode(InventoryItemDetail.self, from: Data(json.utf8))
    }

    func test_init_populatesFieldsFromItem() {
        let api = StubAPIClient(updateResult: .success(.init(id: 42)))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())

        XCTAssertEqual(vm.itemId, 42)
        XCTAssertEqual(vm.name, "Phone case")
        XCTAssertEqual(vm.sku, "CASE-001")
        XCTAssertEqual(vm.upc, "0123456789012")
        XCTAssertEqual(vm.itemType, "product")
        XCTAssertEqual(vm.manufacturer, "Acme")
        XCTAssertEqual(vm.description, "Tempered glass case, clear.")
        XCTAssertEqual(vm.retailPrice, "19.99")
        XCTAssertEqual(vm.costPrice, "2.50")
        XCTAssertEqual(vm.inStock, "12")
        XCTAssertEqual(vm.reorderLevel, "5")
    }

    func test_submit_happyPath_setsDidSave() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 42)))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())
        vm.name = "Phone case — v2"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_withoutName_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 42)))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())
        vm.name = ""

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Name is required.")
    }

    func test_submit_withoutSku_setsValidationError() async {
        let api = StubAPIClient(updateResult: .success(.init(id: 42)))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())
        vm.sku = ""

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "SKU is required.")
    }

    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.networkConnectionLost)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())
        vm.retailPrice = "24.99"

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(404, message: "Item not found")
        let api = StubAPIClient(updateResult: .failure(apiError))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())

        await vm.submit()

        XCTAssertFalse(vm.didSave)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Item not found")
    }

    func test_submit_timeout_queuesOffline() async {
        let urlError = URLError(.timedOut)
        let api = StubAPIClient(updateResult: .failure(urlError))
        let vm = InventoryEditViewModel(api: api, item: sampleItem())

        await vm.submit()

        XCTAssertTrue(vm.didSave)
        XCTAssertTrue(vm.queuedOffline)
    }
}
