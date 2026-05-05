import XCTest
@testable import Hardware

// MARK: - MockPrinterTests

final class MockPrinterTests: XCTestCase {

    // MARK: - isAvailable

    func test_isAvailable_trueByDefault() {
        let mock = MockPrinter()
        XCTAssertTrue(mock.isAvailable())
    }

    func test_isAvailable_false_whenSetToUnavailable() {
        let mock = MockPrinter(available: false)
        XCTAssertFalse(mock.isAvailable())
    }

    // MARK: - printReceipt — success path

    func test_printReceipt_success_capturesPayload() async throws {
        let mock = MockPrinter()
        let payload = Self.samplePayload(receiptNumber: "R-001")

        try await mock.printReceipt(payload)

        XCTAssertEqual(mock.printedPayloads.count, 1)
        XCTAssertEqual(mock.printedPayloads.first?.receiptNumber, "R-001")
    }

    func test_printReceipt_multipleCalls_capturesAll() async throws {
        let mock = MockPrinter()
        let p1 = Self.samplePayload(receiptNumber: "R-001")
        let p2 = Self.samplePayload(receiptNumber: "R-002")
        let p3 = Self.samplePayload(receiptNumber: "R-003")

        try await mock.printReceipt(p1)
        try await mock.printReceipt(p2)
        try await mock.printReceipt(p3)

        XCTAssertEqual(mock.printedPayloads.count, 3)
        XCTAssertEqual(mock.printedPayloads[0].receiptNumber, "R-001")
        XCTAssertEqual(mock.printedPayloads[1].receiptNumber, "R-002")
        XCTAssertEqual(mock.printedPayloads[2].receiptNumber, "R-003")
    }

    // MARK: - printReceipt — failure path

    func test_printReceipt_throwsInjectedError() async {
        let mock = MockPrinter()
        mock.printError = ReceiptPrinterError.printFailed("paper jam")

        do {
            try await mock.printReceipt(Self.samplePayload())
            XCTFail("Expected thrown error")
        } catch ReceiptPrinterError.printFailed(let msg) {
            XCTAssertEqual(msg, "paper jam")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_printReceipt_doesNotCaptureWhenThrowing() async {
        let mock = MockPrinter()
        mock.printError = ReceiptPrinterError.notPaired

        _ = try? await mock.printReceipt(Self.samplePayload())

        XCTAssertTrue(mock.printedPayloads.isEmpty,
                      "Payload must not be captured when print throws")
    }

    // MARK: - openCashDrawer — success path

    func test_openCashDrawer_incrementsKickCount() async throws {
        let mock = MockPrinter()

        try await mock.openCashDrawer()
        try await mock.openCashDrawer()

        XCTAssertEqual(mock.drawerKickCount, 2)
    }

    // MARK: - openCashDrawer — failure path

    func test_openCashDrawer_throwsInjectedError() async {
        let mock = MockPrinter()
        mock.drawerError = ReceiptPrinterError.drawerFailed("stuck")

        do {
            try await mock.openCashDrawer()
            XCTFail("Expected thrown error")
        } catch ReceiptPrinterError.drawerFailed(let msg) {
            XCTAssertEqual(msg, "stuck")
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    func test_openCashDrawer_stillIncrementCountEvenWhenThrowing() async {
        let mock = MockPrinter()
        mock.drawerError = ReceiptPrinterError.drawerFailed("stuck")

        _ = try? await mock.openCashDrawer()

        XCTAssertEqual(mock.drawerKickCount, 1,
                       "drawerKickCount tracks call attempts, not just successes")
    }

    // MARK: - reset

    func test_reset_clearsAllState() async throws {
        let mock = MockPrinter()
        mock.printError = ReceiptPrinterError.notPaired
        mock.drawerError = ReceiptPrinterError.notPaired
        mock.available = false
        _ = try? await mock.printReceipt(Self.samplePayload())
        _ = try? await mock.openCashDrawer()

        mock.reset()

        XCTAssertNil(mock.printError)
        XCTAssertNil(mock.drawerError)
        XCTAssertTrue(mock.available)
        XCTAssertTrue(mock.printedPayloads.isEmpty)
        XCTAssertEqual(mock.drawerKickCount, 0)
    }

    // MARK: - Protocol conformance

    func test_conformsToReceiptPrinter() {
        let mock: any ReceiptPrinter = MockPrinter()
        XCTAssertTrue(mock.isAvailable())
    }

    // MARK: - Helpers

    private static func samplePayload(receiptNumber: String = "R-000") -> ReceiptPayload {
        ReceiptPayload(
            tenantName: "Test Shop",
            tenantAddress: "1 Main St",
            tenantPhone: "555-0000",
            receiptNumber: receiptNumber,
            createdAt: Date(timeIntervalSince1970: 0),
            lineItems: [.init(label: "Item", value: "$9.99")],
            subtotalCents: 999,
            taxCents: 80,
            tipCents: 0,
            totalCents: 1079,
            paymentTender: "Cash",
            cashierName: "Tester"
        )
    }
}
