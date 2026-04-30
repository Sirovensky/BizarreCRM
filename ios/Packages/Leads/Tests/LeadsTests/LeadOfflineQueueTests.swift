import XCTest
@testable import Leads
import Networking

// MARK: - §9.4 LeadOfflineQueue tests

final class LeadOfflineQueueTests: XCTestCase {

    // MARK: - isNetworkError

    func test_urlError_notConnected_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.notConnectedToInternet)))
    }

    func test_urlError_networkConnectionLost_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.networkConnectionLost)))
    }

    func test_urlError_timedOut_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.timedOut)))
    }

    func test_urlError_cannotConnectToHost_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.cannotConnectToHost)))
    }

    func test_urlError_cannotFindHost_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.cannotFindHost)))
    }

    func test_urlError_dnsLookupFailed_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(URLError(.dnsLookupFailed)))
    }

    func test_urlError_badURL_isNotNetwork() {
        XCTAssertFalse(LeadOfflineQueue.isNetworkError(URLError(.badURL)))
    }

    func test_urlError_cancelled_isNotNetwork() {
        XCTAssertFalse(LeadOfflineQueue.isNetworkError(URLError(.cancelled)))
    }

    func test_apiTransportError_code0_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(
            APITransportError.httpStatus(0, message: nil)
        ))
    }

    func test_apiTransportError_400_isNotNetwork() {
        XCTAssertFalse(LeadOfflineQueue.isNetworkError(
            APITransportError.httpStatus(400, message: "Bad Request")
        ))
    }

    func test_apiTransportError_500_isNotNetwork() {
        XCTAssertFalse(LeadOfflineQueue.isNetworkError(
            APITransportError.httpStatus(500, message: "Internal Server Error")
        ))
    }

    func test_apiTransportError_noBaseURL_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(APITransportError.noBaseURL))
    }

    func test_apiTransportError_networkUnavailable_isNetwork() {
        XCTAssertTrue(LeadOfflineQueue.isNetworkError(APITransportError.networkUnavailable))
    }

    // MARK: - encode

    func test_encode_createLeadRequest_containsSnakeCaseKeys() throws {
        let req = CreateLeadRequest(
            firstName: "Ada",
            lastName: "Lovelace",
            email: "ada@example.com",
            phone: "+15555550101",
            source: nil,
            notes: nil,
            company: "Babbage Co",
            title: "Engineer",
            estimatedValueCents: nil,
            stage: "new",
            followUpAt: nil
        )
        let json = try LeadOfflineQueue.encode(req)
        XCTAssertTrue(json.contains("\"first_name\":\"Ada\""),
                      "Expected snake_case first_name, got: \(json)")
        XCTAssertTrue(json.contains("\"last_name\":\"Lovelace\""))
        XCTAssertTrue(json.contains("\"email\":\"ada@example.com\""))
    }

    func test_encode_producesValidUTF8String() throws {
        let req = CreateLeadRequest(
            firstName: "José",
            lastName: nil,
            email: nil,
            phone: nil,
            source: nil,
            notes: "Açaí lover",
            company: nil,
            title: nil,
            estimatedValueCents: nil,
            stage: nil,
            followUpAt: nil
        )
        let json = try LeadOfflineQueue.encode(req)
        XCTAssertFalse(json.isEmpty)
        XCTAssertTrue(json.contains("José"))
    }

    // MARK: - PendingSyncLeadId sentinel

    func test_pendingSyncLeadId_isNegative() {
        XCTAssertLessThan(PendingSyncLeadId, 0)
    }

    func test_pendingSyncLeadId_isMinusOne() {
        XCTAssertEqual(PendingSyncLeadId, -1)
    }
}
