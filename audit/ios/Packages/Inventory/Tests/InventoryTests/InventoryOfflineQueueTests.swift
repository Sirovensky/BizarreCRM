import XCTest
@testable import Inventory
import Networking

final class InventoryOfflineQueueTests: XCTestCase {

    func test_urlError_notConnected_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(URLError(.notConnectedToInternet)))
    }

    func test_urlError_networkConnectionLost_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(URLError(.networkConnectionLost)))
    }

    func test_urlError_timedOut_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(URLError(.timedOut)))
    }

    func test_apiTransportError_code0_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(
            APITransportError.httpStatus(0, message: nil)
        ))
    }

    func test_apiTransportError_400_isNotNetwork() {
        XCTAssertFalse(InventoryOfflineQueue.isNetworkError(
            APITransportError.httpStatus(400, message: "Bad")
        ))
    }

    func test_apiTransportError_500_isNotNetwork() {
        XCTAssertFalse(InventoryOfflineQueue.isNetworkError(
            APITransportError.httpStatus(500, message: "Server")
        ))
    }

    func test_noBaseURL_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(APITransportError.noBaseURL))
    }

    func test_networkUnavailable_isNetwork() {
        XCTAssertTrue(InventoryOfflineQueue.isNetworkError(APITransportError.networkUnavailable))
    }

    func test_encode_createInventoryRequest_roundTrips() throws {
        let req = CreateInventoryItemRequest(
            name: "Phone case",
            itemType: "product",
            sku: "CASE-1",
            retailPrice: 19.99,
            inStock: 10
        )
        let json = try InventoryOfflineQueue.encode(req)
        // Key name must be snake_case — downstream drainer re-decodes this
        // straight into an HTTP body, so the shape must match the server
        // contract verbatim.
        XCTAssertTrue(json.contains("\"item_type\":\"product\""),
                      "Expected snake_case item_type key, got: \(json)")
        XCTAssertTrue(json.contains("\"retail_price\":19.99"))
        XCTAssertTrue(json.contains("\"in_stock\":10"))
    }

    func test_encode_updateInventoryRequest_roundTrips() throws {
        let req = UpdateInventoryItemRequest(
            name: "Phone case — v2",
            retailPrice: 24.99,
            reorderLevel: 3
        )
        let json = try InventoryOfflineQueue.encode(req)
        XCTAssertTrue(json.contains("\"name\":\"Phone case — v2\""))
        XCTAssertTrue(json.contains("\"retail_price\":24.99"))
        XCTAssertTrue(json.contains("\"reorder_level\":3"))
    }
}
