import XCTest
@testable import Hardware

// MARK: - ReceiptPayload rendering tests

final class PrintPayloadTests: XCTestCase {

    // MARK: - ReceiptPayload

    func test_receiptPayload_roundTripsViaJSON() throws {
        let original = Self.sampleReceipt()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReceiptPayload.self, from: data)

        XCTAssertEqual(decoded.tenantName, original.tenantName)
        XCTAssertEqual(decoded.receiptNumber, original.receiptNumber)
        XCTAssertEqual(decoded.totalCents, original.totalCents)
        XCTAssertEqual(decoded.lineItems.count, original.lineItems.count)
    }

    func test_receiptPayload_lineItem_roundTrips() throws {
        let line = ReceiptPayload.Line(label: "Battery", value: "$49.99")
        let data = try JSONEncoder().encode(line)
        let decoded = try JSONDecoder().decode(ReceiptPayload.Line.self, from: data)
        XCTAssertEqual(decoded.label, line.label)
        XCTAssertEqual(decoded.value, line.value)
    }

    func test_receiptPayload_optionalFields_canBeNil() throws {
        let payload = ReceiptPayload(
            tenantName: "Shop",
            tenantAddress: "1 St",
            tenantPhone: "555",
            receiptNumber: "R1",
            createdAt: Date(),
            lineItems: [],
            subtotalCents: 0,
            taxCents: 0,
            tipCents: 0,
            totalCents: 0,
            paymentTender: "Cash",
            cashierName: "Alice"
        )
        XCTAssertNil(payload.footerMessage)
        XCTAssertNil(payload.qrContent)
    }

    func test_receiptPayload_totalsConsistency() {
        let payload = Self.sampleReceipt()
        let derivedTotal = payload.subtotalCents + payload.taxCents + payload.tipCents
        XCTAssertEqual(derivedTotal, payload.totalCents,
                       "subtotal + tax + tip should equal total")
    }

    // MARK: - LabelPayload

    func test_labelPayload_roundTripsViaJSON() throws {
        let original = LabelPayload(
            ticketNumber: "TKT-123",
            customerName: "Jane Doe",
            deviceSummary: "iPhone 15 Pro — cracked screen",
            dateReceived: Date(timeIntervalSince1970: 1_700_000_000),
            qrContent: "https://bizarrecrm.com/t/123",
            size: .medium_2x3
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LabelPayload.self, from: data)
        XCTAssertEqual(decoded.ticketNumber, original.ticketNumber)
        XCTAssertEqual(decoded.size, original.size)
        XCTAssertEqual(decoded.qrContent, original.qrContent)
    }

    func test_labelSize_small_hasCorrectPoints() {
        XCTAssertEqual(LabelSize.small_2x1.pointSize.width, 144)
        XCTAssertEqual(LabelSize.small_2x1.pointSize.height, 72)
    }

    func test_labelSize_medium_hasCorrectPoints() {
        XCTAssertEqual(LabelSize.medium_2x3.pointSize.width, 144)
        XCTAssertEqual(LabelSize.medium_2x3.pointSize.height, 216)
    }

    func test_labelSize_large_hasCorrectPoints() {
        XCTAssertEqual(LabelSize.large_4x6.pointSize.width, 288)
        XCTAssertEqual(LabelSize.large_4x6.pointSize.height, 432)
    }

    func test_labelSize_caseIterable_hasThreeCases() {
        XCTAssertEqual(LabelSize.allCases.count, 3)
    }

    // MARK: - TicketTagPayload

    func test_ticketTagPayload_roundTripsViaJSON() throws {
        let original = TicketTagPayload(
            ticketNumber: "TKT-456",
            customerName: "Bob Smith",
            deviceModel: "MacBook Air M2",
            promisedBy: Date(timeIntervalSince1970: 1_710_000_000),
            qrContent: "https://bizarrecrm.com/t/456"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TicketTagPayload.self, from: data)
        XCTAssertEqual(decoded.ticketNumber, original.ticketNumber)
        XCTAssertEqual(decoded.customerName, original.customerName)
        XCTAssertNotNil(decoded.promisedBy)
    }

    func test_ticketTagPayload_nilPromisedBy_decodesCorrectly() throws {
        let original = TicketTagPayload(
            ticketNumber: "TKT-789",
            customerName: "Alice",
            deviceModel: "iPad Pro",
            promisedBy: nil,
            qrContent: "qr://test"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TicketTagPayload.self, from: data)
        XCTAssertNil(decoded.promisedBy)
    }

    // MARK: - BarcodePayload

    func test_barcodePayload_allFormats_roundTrip() throws {
        for format in [BarcodeFormat.code128, .upca, .ean13, .qr] {
            let payload = BarcodePayload(code: "TEST123", format: format)
            let data = try JSONEncoder().encode(payload)
            let decoded = try JSONDecoder().decode(BarcodePayload.self, from: data)
            XCTAssertEqual(decoded.format, format)
            XCTAssertEqual(decoded.code, payload.code)
        }
    }

    // MARK: - PrintEngine models

    func test_printer_hashable_identicalStructsAreEqual() {
        let conn = PrinterConnection.network(host: "1.2.3.4", port: 9100)
        let a = Printer(id: "p1", name: "A", kind: .thermalReceipt, connection: conn)
        let b = Printer(id: "p1", name: "A", kind: .thermalReceipt, connection: conn)
        XCTAssertEqual(a, b, "Two identical Printers must be equal")
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_printer_setContainment_usesHashable() {
        let conn = PrinterConnection.network(host: "1.2.3.4", port: 9100)
        let a = Printer(id: "p1", name: "A", kind: .thermalReceipt, connection: conn)
        let b = Printer(id: "p1", name: "A", kind: .thermalReceipt, connection: conn)
        let set: Set<Printer> = [a, b]
        XCTAssertEqual(set.count, 1, "Identical printers should deduplicate in a Set")
    }

    func test_printer_withStatus_immutableUpdate() {
        let original = Printer(id: "x", name: "X", kind: .thermalReceipt, connection: .network(host: "h", port: 1))
        let updated = original.withStatus(.printing)
        XCTAssertEqual(original.status, .idle)
        XCTAssertEqual(updated.status, .printing)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.name, original.name)
    }

    func test_printerConnection_displayString_networkContainsHostAndPort() {
        let conn = PrinterConnection.network(host: "10.0.0.1", port: 9100)
        XCTAssertTrue(conn.displayString.contains("10.0.0.1"))
        XCTAssertTrue(conn.displayString.contains("9100"))
    }

    func test_printerConnection_displayString_airPrintContainsHost() {
        let url = URL(string: "ipp://myprinter.local/ipp/print")!
        let conn = PrinterConnection.airPrint(url: url)
        XCTAssertTrue(conn.displayString.contains("myprinter.local"))
    }

    func test_printerConnection_displayString_bluetoothContainsId() {
        let conn = PrinterConnection.bluetoothMFi(id: "ABC-123-DEF")
        XCTAssertTrue(conn.displayString.contains("ABC-123-DEF"))
    }

    func test_printEngineError_descriptions_arePopulated() {
        let cases: [PrintEngineError] = [
            .printerNotReachable("p1"),
            .unsupportedJobKind(.label),
            .renderFailed("bad render"),
            .sendFailed("IO"),
            .noPrinterConfigured,
            .cancelled
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription, "Error \(error) must have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    // MARK: - Helpers

    private static func sampleReceipt() -> ReceiptPayload {
        ReceiptPayload(
            tenantName: "Weird Fix Shop",
            tenantAddress: "789 Oak Ave",
            tenantPhone: "(800) 999-1234",
            receiptNumber: "R-4567",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lineItems: [
                .init(label: "Screen replacement", value: "$120.00"),
                .init(label: "Parts", value: "$45.00")
            ],
            subtotalCents: 16500,
            taxCents: 1320,
            tipCents: 0,
            totalCents: 17820,
            paymentTender: "Visa ••••5678",
            cashierName: "Carlos",
            footerMessage: "Thank you!",
            qrContent: "https://tracking.example.com/R-4567"
        )
    }
}
