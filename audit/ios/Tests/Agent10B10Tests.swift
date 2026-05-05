import XCTest
@testable import Core

// MARK: - Agent-10 batch-10 tests
//
// Covers:
//   §1.5  AppRoute typed enums
//   §1    SceneUndoManager
//   §63.5 SoftDeleteUndoService
//   §32.0 TelemetryRequestSigner

// MARK: - §1.5 AppRoute Tests

final class AppRouteTests: XCTestCase {

    // TicketsRoute

    func testTicketsRouteHashable() {
        let a = TicketsRoute.detail(id: 42)
        let b = TicketsRoute.detail(id: 42)
        let c = TicketsRoute.detail(id: 99)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTicketsRouteCodable() throws {
        let route = TicketsRoute.detail(id: 123)
        let data  = try JSONEncoder().encode(route)
        let back  = try JSONDecoder().decode(TicketsRoute.self, from: data)
        XCTAssertEqual(route, back)
    }

    func testTicketsRouteList() {
        let route = TicketsRoute.list
        XCTAssertEqual(route, .list)
    }

    func testAllRouteEnumsCodable() throws {
        // CustomersRoute
        let cust = CustomersRoute.detail(id: 7)
        let custData = try JSONEncoder().encode(cust)
        let custBack = try JSONDecoder().decode(CustomersRoute.self, from: custData)
        XCTAssertEqual(cust, custBack)

        // InventoryRoute
        let inv = InventoryRoute.scan
        let invData = try JSONEncoder().encode(inv)
        let invBack = try JSONDecoder().decode(InventoryRoute.self, from: invData)
        XCTAssertEqual(inv, invBack)

        // POSRoute
        let pos = POSRoute.cart
        let posData = try JSONEncoder().encode(pos)
        let posBack = try JSONDecoder().decode(POSRoute.self, from: posData)
        XCTAssertEqual(pos, posBack)

        // AppTabRoute
        let tab = AppTabRoute.tickets
        let tabData = try JSONEncoder().encode(tab)
        let tabBack = try JSONDecoder().decode(AppTabRoute.self, from: tabData)
        XCTAssertEqual(tab, tabBack)
    }

    func testSettingsRouteHashable() {
        var set: Set<SettingsRoute> = []
        set.insert(.root)
        set.insert(.profile)
        set.insert(.root)  // duplicate
        XCTAssertEqual(set.count, 2)
    }

    func testSMSRouteWithPrefill() {
        let route = SMSRoute.compose(prefillPhone: "+15551234567")
        let set: Set<SMSRoute> = [route, .threadList]
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - §1 SceneUndoManager Tests

@MainActor
final class SceneUndoManagerTests: XCTestCase {

    var manager: SceneUndoManager!

    override func setUp() {
        super.setUp()
        manager = SceneUndoManager()
    }

    func testInitialState() {
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
        XCTAssertNil(manager.undoActionDescription)
    }

    func testRegisterAndUndo() async {
        var value = "original"
        manager.registerUndo(
            description: "Change value",
            undo: { value = "original" },
            redo: { value = "changed"  }
        )
        value = "changed"
        XCTAssertTrue(manager.canUndo)
        XCTAssertEqual(manager.undoActionDescription, "Change value")

        await manager.undo()
        XCTAssertEqual(value, "original")
        XCTAssertFalse(manager.canUndo)
        XCTAssertTrue(manager.canRedo)
    }

    func testRedo() async {
        var value = "original"
        manager.registerUndo(
            description: "Change value",
            undo: { value = "original" },
            redo: { value = "changed"  }
        )
        value = "changed"
        await manager.undo()
        XCTAssertFalse(manager.canRedo == false, "Should be able to redo")
        await manager.redo()
        XCTAssertEqual(value, "changed")
    }

    func testNewActionClearsRedoStack() async {
        var value = "a"
        manager.registerUndo(description: "A", undo: { value = "a" }, redo: { value = "b" })
        value = "b"
        await manager.undo()
        XCTAssertTrue(manager.canRedo)

        // Register new action — redo stack must clear
        manager.registerUndo(description: "C", undo: { value = "b" }, redo: { value = "c" })
        XCTAssertFalse(manager.canRedo)
    }

    func testClearAll() {
        manager.registerUndo(description: "X", undo: {}, redo: {})
        XCTAssertTrue(manager.canUndo)
        manager.clearAll()
        XCTAssertFalse(manager.canUndo)
        XCTAssertFalse(manager.canRedo)
    }

    func testMaxDepth() {
        for i in 0..<60 {
            manager.registerUndo(description: "Op\(i)", undo: {}, redo: {})
        }
        // Stack is capped at 50 — the first 10 were dropped.
        XCTAssertTrue(manager.canUndo)
        XCTAssertEqual(manager.undoActionDescription, "Op59")
    }
}

// MARK: - §63.5 SoftDeleteUndoService Tests

@MainActor
final class SoftDeleteUndoServiceTests: XCTestCase {

    var service: SoftDeleteUndoService!

    override func setUp() {
        super.setUp()
        service = SoftDeleteUndoService()
    }

    func testInitialStateNil() {
        XCTAssertNil(service.activeEntry)
    }

    func testPerformDeleteSetsEntry() {
        let expectSoftDelete = expectation(description: "softDelete called")
        service.performDelete(
            label: "Ticket #1",
            undoWindow: 60,
            softDelete: { expectSoftDelete.fulfill() },
            undo: {}
        )
        wait(for: [expectSoftDelete], timeout: 1)
        XCTAssertNotNil(service.activeEntry)
        XCTAssertEqual(service.activeEntry?.label, "Ticket #1")
    }

    func testPerformUndoRevertsEntry() {
        let expectSoftDelete = expectation(description: "softDelete called")
        let expectUndo       = expectation(description: "undo called")
        service.performDelete(
            label: "Ticket #2",
            undoWindow: 60,
            softDelete: { expectSoftDelete.fulfill() },
            undo:       { expectUndo.fulfill() }
        )
        wait(for: [expectSoftDelete], timeout: 1)
        service.performUndo()
        wait(for: [expectUndo], timeout: 1)
        XCTAssertNil(service.activeEntry, "Entry should clear after undo")
    }

    func testSecondDeleteReplacesFirst() {
        service.performDelete(label: "First",  undoWindow: 60, softDelete: {}, undo: {})
        service.performDelete(label: "Second", undoWindow: 60, softDelete: {}, undo: {})
        XCTAssertEqual(service.activeEntry?.label, "Second")
    }
}

// MARK: - §32.0 TelemetryRequestSigner Tests

final class TelemetryRequestSignerTests: XCTestCase {

    func testSignAddsAuthHeader() {
        let signer = TelemetryRequestSigner(token: "test-token-abc")
        var req = URLRequest(url: URL(string: "https://shop.bizarrecrm.com/telemetry/events")!)
        signer.sign(&req)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-token-abc")
    }

    func testSignWithNilTokenNoHeader() {
        let signer = TelemetryRequestSigner(token: nil)
        var req = URLRequest(url: URL(string: "https://shop.bizarrecrm.com/telemetry/events")!)
        signer.sign(&req)
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testSignFunctionVariant() {
        let signer = TelemetryRequestSigner(token: "xyz")
        let req = URLRequest(url: URL(string: "https://example.com")!)
        let signed = signer.sign(req)
        XCTAssertEqual(signed.value(forHTTPHeaderField: "Authorization"), "Bearer xyz")
        // Original request unchanged
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testUpdateAndClearShadow() {
        TelemetryRequestSigner.updateTokenShadow("shadow-tok")
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "telemetry.access_token_shadow"),
            "shadow-tok"
        )
        TelemetryRequestSigner.clearTokenShadow()
        XCTAssertNil(UserDefaults.standard.string(forKey: "telemetry.access_token_shadow"))
    }
}

// MARK: - §31.1 MockURLProtocol Tests (basic)

final class MockURLProtocolTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testRespondWithEnvelopeSuccess() async throws {
        MockURLProtocol.respondWithEnvelope(statusCode: 200, success: true)
        let config = MockURLProtocol.ephemeralConfiguration()
        let session = URLSession(configuration: config)
        let url = URL(string: "https://test.invalid/api/v1/tickets")!
        let (data, response) = try await session.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["success"] as? Bool, true)
    }

    func testRequestIsRecorded() async throws {
        MockURLProtocol.respondWithEnvelope()
        let config = MockURLProtocol.ephemeralConfiguration()
        let session = URLSession(configuration: config)
        let url = URL(string: "https://test.invalid/ping")!
        _ = try? await session.data(from: url)
        XCTAssertEqual(MockURLProtocol.recordedRequests.count, 1)
        XCTAssertEqual(MockURLProtocol.recordedRequests.first?.url, url)
    }

    func testMissingHandlerReturnsError() async {
        MockURLProtocol.requestHandler = nil
        let config = MockURLProtocol.ephemeralConfiguration()
        let session = URLSession(configuration: config)
        let url = URL(string: "https://test.invalid/missing")!
        do {
            _ = try await session.data(from: url)
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
