import XCTest
@testable import Inventory
import Networking

@MainActor
final class InventoryCreateViewModelTests: XCTestCase {

    // Happy path: the API returns a created id; vm.createdId is populated.
    func test_submit_happyPath_populatesCreatedId() async {
        let api = StubAPIClient(createResult: .success(.init(id: 99)))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = "Widget"
        vm.sku = "WDG-001"

        await vm.submit()

        XCTAssertEqual(vm.createdId, 99)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Validation: without a name, submit bails early with a message.
    func test_submit_withoutName_setsValidationError() async {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = ""
        vm.sku = "SKU-01"

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Name is required.")
    }

    // Validation: without a SKU, submit bails early with a message.
    func test_submit_withoutSku_setsValidationError() async {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = "Phone case"
        vm.sku = ""

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "SKU is required.")
    }

    // Offline: a transport error is redirected into the queue, createdId is
    // set to the pending sentinel and no user-facing error surfaces.
    func test_submit_networkError_queuesOffline() async {
        let urlError = URLError(.notConnectedToInternet)
        let api = StubAPIClient(createResult: .failure(urlError))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = "Widget"
        vm.sku = "WDG-002"

        await vm.submit()

        XCTAssertEqual(vm.createdId, PendingSyncInventoryId)
        XCTAssertTrue(vm.queuedOffline)
        XCTAssertNil(vm.errorMessage)
    }

    // Non-network 4xx-style errors surface verbatim — we do NOT queue them,
    // because the server has told us the payload is bad.
    func test_submit_serverError_surfacesMessage() async {
        let apiError = APITransportError.httpStatus(400, message: "Invalid item_type")
        let api = StubAPIClient(createResult: .failure(apiError))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = "Widget"
        vm.sku = "WDG-003"

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertFalse(vm.queuedOffline)
        XCTAssertEqual(vm.errorMessage, "Invalid item_type")
    }

    // isValid reflects both required fields — flipping either blanks it out.
    func test_isValid_requiresBothNameAndSku() {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = InventoryCreateViewModel(api: api)
        XCTAssertFalse(vm.isValid)

        vm.name = "Phone case"
        XCTAssertFalse(vm.isValid)

        vm.sku = "CASE-01"
        XCTAssertTrue(vm.isValid)

        vm.sku = "   "
        XCTAssertFalse(vm.isValid)
    }

    // Whitespace-only input shouldn't pass validation even on the server side —
    // we strip it before send.
    func test_submit_whitespaceOnlyName_setsValidationError() async {
        let api = StubAPIClient(createResult: .success(.init(id: 1)))
        let vm = InventoryCreateViewModel(api: api)
        vm.name = "   \n\t"
        vm.sku = "WDG-009"

        await vm.submit()

        XCTAssertNil(vm.createdId)
        XCTAssertEqual(vm.errorMessage, "Name is required.")
    }
}
