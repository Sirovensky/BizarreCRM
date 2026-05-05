import XCTest
@testable import Customers
import Networking

final class CustomerOfflineQueueTests: XCTestCase {

    func test_urlError_notConnected_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(URLError(.notConnectedToInternet)))
    }

    func test_urlError_networkConnectionLost_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(URLError(.networkConnectionLost)))
    }

    func test_urlError_timedOut_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(URLError(.timedOut)))
    }

    func test_apiTransportError_code0_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(
            APITransportError.httpStatus(0, message: nil)
        ))
    }

    func test_apiTransportError_400_isNotNetwork() {
        XCTAssertFalse(CustomerOfflineQueue.isNetworkError(
            APITransportError.httpStatus(400, message: "Bad")
        ))
    }

    func test_apiTransportError_500_isNotNetwork() {
        XCTAssertFalse(CustomerOfflineQueue.isNetworkError(
            APITransportError.httpStatus(500, message: "Server")
        ))
    }

    func test_noBaseURL_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(APITransportError.noBaseURL))
    }

    func test_networkUnavailable_isNetwork() {
        XCTAssertTrue(CustomerOfflineQueue.isNetworkError(APITransportError.networkUnavailable))
    }

    func test_encode_createCustomerRequest_roundTrips() throws {
        let req = CreateCustomerRequest(
            firstName: "Ada",
            lastName: "Lovelace",
            email: "ada@example.com",
            phone: "+15555550101"
        )
        let json = try CustomerOfflineQueue.encode(req)
        // Key name must be snake_case — downstream drainer re-decodes this
        // straight into an HTTP body, so the shape must match the server
        // contract verbatim.
        XCTAssertTrue(json.contains("\"first_name\":\"Ada\""),
                      "Expected snake_case first_name key, got: \(json)")
        XCTAssertTrue(json.contains("\"last_name\":\"Lovelace\""))
    }

    func test_encode_updateCustomerRequest_roundTrips() throws {
        let req = UpdateCustomerRequest(firstName: "Grace", lastName: "Hopper")
        let json = try CustomerOfflineQueue.encode(req)
        XCTAssertTrue(json.contains("\"first_name\":\"Grace\""))
        XCTAssertTrue(json.contains("\"last_name\":\"Hopper\""))
    }
}
