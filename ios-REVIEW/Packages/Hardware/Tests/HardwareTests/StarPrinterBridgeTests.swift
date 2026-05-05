import XCTest
@testable import Hardware

// MARK: - StarPrinterBridgeTests
//
// Tests for `MockStarPrinterBridge` and `StarPrinterAdapter`.
// Real `StarPrinterBridge` requires a live CBPeripheral — tested via simulator
// integration tests when MFi hardware is available. This suite covers the
// pure-logic layer: the adapter's protocol conformance and error mapping.

final class StarPrinterBridgeTests: XCTestCase {

    // MARK: - MockStarPrinterBridge — basic behaviour

    func test_mockBridge_initiallyNotConnected() async {
        let bridge = MockStarPrinterBridge()
        let connected = await bridge.isConnected
        XCTAssertFalse(connected)
    }

    func test_mockBridge_initiallyConnected_whenPassedTrue() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        let connected = await bridge.isConnected
        XCTAssertTrue(connected)
    }

    func test_mockBridge_connect_setsConnected() async throws {
        let bridge = MockStarPrinterBridge()
        try await bridge.connect()
        let connected = await bridge.isConnected
        XCTAssertTrue(connected)
    }

    func test_mockBridge_connect_incrementsCallCount() async throws {
        let bridge = MockStarPrinterBridge()
        try await bridge.connect()
        try await bridge.connect()
        let count = await bridge.connectCallCount
        XCTAssertEqual(count, 2)
    }

    func test_mockBridge_connect_throwsInjectedError() async {
        let bridge = MockStarPrinterBridge()
        await bridge.set(connectError: StarPrinterBridgeError.characteristicNotFound)
        do {
            try await bridge.connect()
            XCTFail("Expected thrown error")
        } catch StarPrinterBridgeError.characteristicNotFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_mockBridge_send_appendsData() async throws {
        let bridge = MockStarPrinterBridge(isConnected: true)
        let d1 = Data([0x01, 0x02])
        let d2 = Data([0x03, 0x04])
        try await bridge.send(d1)
        try await bridge.send(d2)
        let sent = await bridge.sentData
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0], d1)
        XCTAssertEqual(sent[1], d2)
    }

    func test_mockBridge_send_throwsInjectedError() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        await bridge.set(sendError: StarPrinterBridgeError.writeFailed("timeout"))
        do {
            try await bridge.send(Data([0xFF]))
            XCTFail("Expected thrown error")
        } catch StarPrinterBridgeError.writeFailed(let msg) {
            XCTAssertEqual(msg, "timeout")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_mockBridge_disconnect_clearsConnected() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        await bridge.disconnect()
        let connected = await bridge.isConnected
        XCTAssertFalse(connected)
    }

    func test_mockBridge_disconnect_incrementsCallCount() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        await bridge.disconnect()
        await bridge.disconnect()
        let count = await bridge.disconnectCallCount
        XCTAssertEqual(count, 2)
    }

    func test_mockBridge_reset_clearsAll() async throws {
        let bridge = MockStarPrinterBridge(isConnected: true)
        try await bridge.send(Data([0xAA]))
        try await bridge.connect()
        await bridge.reset()

        let connected = await bridge.isConnected
        let sent = await bridge.sentData
        let callCount = await bridge.connectCallCount
        XCTAssertFalse(connected)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - StarPrinterAdapter — printReceipt

    func test_adapter_printReceipt_sendsNonEmptyBytes() async throws {
        let bridge = MockStarPrinterBridge(isConnected: true)
        let adapter = StarPrinterAdapter(bridge: bridge)
        let payload = Self.samplePayload()

        try await adapter.printReceipt(payload)

        let sent = await bridge.sentData
        XCTAssertFalse(sent.isEmpty, "printReceipt must send bytes to the bridge")
        // The ESC/POS stream always starts with ESC @ (0x1B, 0x40)
        XCTAssertEqual(sent[0].prefix(2), Data([0x1B, 0x40]),
                       "First bytes sent must be ESC @ (initialize)")
    }

    func test_adapter_printReceipt_connectsIfNotAlreadyConnected() async throws {
        let bridge = MockStarPrinterBridge(isConnected: false)
        let adapter = StarPrinterAdapter(bridge: bridge)

        try await adapter.printReceipt(Self.samplePayload())

        let callCount = await bridge.connectCallCount
        XCTAssertEqual(callCount, 1, "Adapter must call connect() when bridge is not connected")
    }

    func test_adapter_printReceipt_skipsConnectWhenAlreadyConnected() async throws {
        let bridge = MockStarPrinterBridge(isConnected: true)
        let adapter = StarPrinterAdapter(bridge: bridge)

        try await adapter.printReceipt(Self.samplePayload())

        let callCount = await bridge.connectCallCount
        XCTAssertEqual(callCount, 0, "Adapter must not redundantly call connect() if already connected")
    }

    func test_adapter_printReceipt_wrapsWriteErrorAsPrintFailed() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        await bridge.set(sendError: StarPrinterBridgeError.writeFailed("IO error"))
        let adapter = StarPrinterAdapter(bridge: bridge)

        do {
            try await adapter.printReceipt(Self.samplePayload())
            XCTFail("Expected ReceiptPrinterError.printFailed")
        } catch ReceiptPrinterError.printFailed {
            // expected — adapter maps bridge errors to ReceiptPrinterError
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - StarPrinterAdapter — openCashDrawer

    func test_adapter_openCashDrawer_sends5ByteDrawerKickCommand() async throws {
        let bridge = MockStarPrinterBridge(isConnected: true)
        let adapter = StarPrinterAdapter(bridge: bridge)

        try await adapter.openCashDrawer()

        let sent = await bridge.sentData
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].count, 5, "Drawer kick must be exactly 5 bytes")
        // ESC p 0 t1 t2
        XCTAssertEqual(sent[0][0], 0x1B)
        XCTAssertEqual(sent[0][1], 0x70)
    }

    func test_adapter_openCashDrawer_throwsNotPairedWhenNotConnected() async {
        let bridge = MockStarPrinterBridge(isConnected: false)
        let adapter = StarPrinterAdapter(bridge: bridge)

        do {
            try await adapter.openCashDrawer()
            XCTFail("Expected ReceiptPrinterError.notPaired")
        } catch ReceiptPrinterError.notPaired {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func test_adapter_openCashDrawer_wrapsWriteErrorAsDrawerFailed() async {
        let bridge = MockStarPrinterBridge(isConnected: true)
        await bridge.set(sendError: StarPrinterBridgeError.writeFailed("stuck"))
        let adapter = StarPrinterAdapter(bridge: bridge)

        do {
            try await adapter.openCashDrawer()
            XCTFail("Expected ReceiptPrinterError.drawerFailed")
        } catch ReceiptPrinterError.drawerFailed {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - StarPrinterBridgeError descriptions

    func test_errorDescriptions_areNonEmpty() {
        let cases: [StarPrinterBridgeError] = [
            .notConnected,
            .characteristicNotFound,
            .writeFailed("test"),
            .disconnected
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription,
                            "Error \(error) must have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func test_writeFailed_descriptionContainsDetail() {
        let error = StarPrinterBridgeError.writeFailed("timeout after 5s")
        XCTAssertTrue(error.errorDescription?.contains("timeout after 5s") == true)
    }

    // MARK: - Helpers

    private static func samplePayload() -> ReceiptPayload {
        ReceiptPayload(
            tenantName: "Star Print Test",
            tenantAddress: "1 Thermal Rd",
            tenantPhone: "555-9999",
            receiptNumber: "STAR-001",
            createdAt: Date(timeIntervalSince1970: 0),
            lineItems: [.init(label: "Test Item", value: "$5.00")],
            subtotalCents: 500,
            taxCents: 40,
            tipCents: 0,
            totalCents: 540,
            paymentTender: "Card",
            cashierName: "Robot"
        )
    }
}

// MARK: - MockStarPrinterBridge test helpers

extension MockStarPrinterBridge {
    func set(connectError: Error?) async { self.connectError = connectError }
    func set(sendError: Error?) async { self.sendError = sendError }
}
