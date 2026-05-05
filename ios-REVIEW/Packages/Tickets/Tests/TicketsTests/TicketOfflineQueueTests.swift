import XCTest
@testable import Tickets
import Networking
import Persistence

final class TicketOfflineQueueTests: XCTestCase {

    func test_urlError_notConnected_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(URLError(.notConnectedToInternet)))
    }

    func test_urlError_networkConnectionLost_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(URLError(.networkConnectionLost)))
    }

    func test_urlError_timedOut_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(URLError(.timedOut)))
    }

    func test_urlError_cannotConnectToHost_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(URLError(.cannotConnectToHost)))
    }

    func test_apiTransportError_code0_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(
            APITransportError.httpStatus(0, message: nil)
        ))
    }

    func test_apiTransportError_400_isNotNetwork() {
        XCTAssertFalse(TicketOfflineQueue.isNetworkError(
            APITransportError.httpStatus(400, message: "Bad")
        ))
    }

    func test_apiTransportError_403_isNotNetwork() {
        // Tickets are permission-gated (requirePermission('tickets.edit'));
        // a 403 means the token lacks the permission — retrying the same
        // request would never succeed, so it must NOT queue.
        XCTAssertFalse(TicketOfflineQueue.isNetworkError(
            APITransportError.httpStatus(403, message: "No permission")
        ))
    }

    func test_apiTransportError_409_isNotNetwork() {
        // Optimistic-lock conflict from the PUT route — surface to user,
        // don't silently queue.
        XCTAssertFalse(TicketOfflineQueue.isNetworkError(
            APITransportError.httpStatus(409, message: "Conflict")
        ))
    }

    func test_apiTransportError_500_isNotNetwork() {
        XCTAssertFalse(TicketOfflineQueue.isNetworkError(
            APITransportError.httpStatus(500, message: "Server")
        ))
    }

    func test_noBaseURL_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(APITransportError.noBaseURL))
    }

    func test_networkUnavailable_isNetwork() {
        XCTAssertTrue(TicketOfflineQueue.isNetworkError(APITransportError.networkUnavailable))
    }

    func test_encode_createTicketRequest_roundTrips() throws {
        let device = CreateTicketRequest.NewDevice(
            deviceName: "iPhone 14",
            imei: "123456789012345",
            serial: "SN-1",
            additionalNotes: "Won't boot",
            price: 150
        )
        let req = CreateTicketRequest(customerId: 42, devices: [device])
        let json = try TicketOfflineQueue.encode(req)

        // Key name must be snake_case — downstream drainer re-decodes
        // this straight into an HTTP body, so the shape must match the
        // server contract verbatim.
        XCTAssertTrue(json.contains("\"customer_id\":42"),
                      "Expected snake_case customer_id, got: \(json)")
        XCTAssertTrue(json.contains("\"device_name\":\"iPhone 14\""))
        XCTAssertTrue(json.contains("\"additional_notes\":\"Won't boot\""))
    }

    func test_encode_updateTicketRequest_roundTrips() throws {
        let req = UpdateTicketRequest(
            discount: 25,
            discountReason: "Loyalty",
            source: "organic"
        )
        let json = try TicketOfflineQueue.encode(req)
        XCTAssertTrue(json.contains("\"discount\":25"))
        XCTAssertTrue(json.contains("\"discount_reason\":\"Loyalty\""))
        XCTAssertTrue(json.contains("\"source\":\"organic\""))
    }

    func test_syncQueueRecord_forTicketCreate_hasExpectedShape() {
        // Spot-check the shared `SyncQueueRecord` constructor wrapped by
        // `TicketOfflineQueue.enqueue`. The drainer keys off `entity` +
        // `op` to route to the right HTTP verb / URL.
        let record = SyncQueueRecord(
            op: "create",
            entity: "ticket",
            payload: "{}"
        )
        XCTAssertEqual(record.op, "create")
        XCTAssertEqual(record.entity, "ticket")
        XCTAssertEqual(record.kind, "ticket.create")
        XCTAssertEqual(record.status, SyncQueueRecord.Status.queued.rawValue)
        XCTAssertFalse(record.idempotencyKey?.isEmpty ?? true,
                       "idempotency key must default to a UUID so retries dedupe")
    }

    func test_syncQueueRecord_forTicketUpdate_carriesServerId() {
        let record = SyncQueueRecord(
            op: "update",
            entity: "ticket",
            entityLocalId: nil,
            entityServerId: "42",
            payload: "{}"
        )
        XCTAssertEqual(record.op, "update")
        XCTAssertEqual(record.entity, "ticket")
        XCTAssertEqual(record.entityServerId, "42")
        XCTAssertEqual(record.kind, "ticket.update")
    }
}
