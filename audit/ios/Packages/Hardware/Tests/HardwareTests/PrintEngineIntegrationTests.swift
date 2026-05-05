import XCTest
@testable import Hardware

// MARK: - PrintEngineIntegrationTests
//
// Integration-level tests for the PrintEngine protocol conformances using the
// controllable `MockPrintEngine`. Exercises the PrintJob + Printer model
// pairing and validates that `JobPayload` round-trips through the engine
// correctly.
//
// Note: these tests do NOT hit real printers. They use the mock engine that
// is already tested in `PrintJobQueueTests`. This suite focuses on the
// cross-cutting scenarios not covered elsewhere:
//   - `PrintJob` with every `JobPayload` variant produces a Sendable payload.
//   - `Printer.withStatus` immutability (belt-and-suspenders beyond queue tests).
//   - `PrintEngineError.Equatable` conformance for branching in callers.

final class PrintEngineIntegrationTests: XCTestCase {

    // MARK: - PrintJob construction for every payload variant

    func test_printJob_receiptPayload_kindIsReceipt() {
        let job = Self.makeReceiptJob()
        XCTAssertEqual(job.kind, .receipt)
        if case .receipt = job.payload { /* ok */ } else {
            XCTFail("Payload must be .receipt")
        }
    }

    func test_printJob_labelPayload_kindIsLabel() {
        let job = Self.makeLabelJob()
        XCTAssertEqual(job.kind, .label)
        if case .label = job.payload { /* ok */ } else {
            XCTFail("Payload must be .label")
        }
    }

    func test_printJob_ticketTagPayload_kindIsTicketTag() {
        let job = Self.makeTicketTagJob()
        XCTAssertEqual(job.kind, .ticketTag)
        if case .ticketTag = job.payload { /* ok */ } else {
            XCTFail("Payload must be .ticketTag")
        }
    }

    func test_printJob_barcodePayload_kindIsBarcode() {
        let job = Self.makeBarcodeJob()
        XCTAssertEqual(job.kind, .barcode)
        if case .barcode = job.payload { /* ok */ } else {
            XCTFail("Payload must be .barcode")
        }
    }

    // MARK: - MockPrintEngine dispatches all payload variants

    func test_mockEngine_printsAllPayloadVariants() async throws {
        let engine = MockPrintEngine(failCount: 0)
        let printer = Self.makePrinter()

        let jobs: [PrintJob] = [
            Self.makeReceiptJob(),
            Self.makeLabelJob(),
            Self.makeTicketTagJob(),
            Self.makeBarcodeJob()
        ]

        for job in jobs {
            try await engine.print(job, on: printer)
        }

        XCTAssertEqual(engine.printCallCount, 4)
    }

    // MARK: - Printer.withStatus immutability (cross-verification)

    func test_printer_withStatus_error_preservesId() {
        let printer = Self.makePrinter()
        let updated = printer.withStatus(.error("paper jam"))
        XCTAssertEqual(printer.status, .idle)
        if case .error(let msg) = updated.status {
            XCTAssertEqual(msg, "paper jam")
        } else {
            XCTFail("Status must be .error")
        }
        XCTAssertEqual(updated.id, printer.id)
        XCTAssertEqual(updated.name, printer.name)
    }

    func test_printer_withStatus_printing_isNotIdle() {
        let printer = Self.makePrinter()
        let printing = printer.withStatus(.printing)
        XCTAssertNotEqual(printing.status, .idle)
        XCTAssertEqual(printing.status, .printing)
    }

    // MARK: - PrintEngineError.Equatable

    func test_printEngineError_equatable_sameCase_equal() {
        XCTAssertEqual(PrintEngineError.cancelled, PrintEngineError.cancelled)
        XCTAssertEqual(PrintEngineError.noPrinterConfigured, PrintEngineError.noPrinterConfigured)
        XCTAssertEqual(PrintEngineError.printerNotReachable("x"), PrintEngineError.printerNotReachable("x"))
        XCTAssertEqual(PrintEngineError.renderFailed("r"), PrintEngineError.renderFailed("r"))
        XCTAssertEqual(PrintEngineError.sendFailed("s"), PrintEngineError.sendFailed("s"))
        XCTAssertEqual(PrintEngineError.unsupportedJobKind(.label), PrintEngineError.unsupportedJobKind(.label))
    }

    func test_printEngineError_equatable_differentCases_notEqual() {
        XCTAssertNotEqual(PrintEngineError.cancelled, PrintEngineError.noPrinterConfigured)
        XCTAssertNotEqual(PrintEngineError.printerNotReachable("a"), PrintEngineError.printerNotReachable("b"))
    }

    // MARK: - JobKind raw values (regression: stable API surface)

    func test_jobKind_rawValues_areStable() {
        XCTAssertEqual(JobKind.receipt.rawValue, "receipt")
        XCTAssertEqual(JobKind.label.rawValue, "label")
        XCTAssertEqual(JobKind.ticketTag.rawValue, "ticketTag")
        XCTAssertEqual(JobKind.barcode.rawValue, "barcode")
    }

    // MARK: - Printer connection display strings

    func test_printerConnection_airPrint_displayStringContainsAirPrint() {
        let url = URL(string: "ipp://myprinter.local/ipp/print")!
        let conn = PrinterConnection.airPrint(url: url)
        XCTAssertTrue(conn.displayString.contains("AirPrint"))
    }

    func test_printerConnection_network_displayStringContainsNetwork() {
        let conn = PrinterConnection.network(host: "1.2.3.4", port: 9100)
        XCTAssertTrue(conn.displayString.contains("Network"))
    }

    func test_printerConnection_bluetoothMFi_displayStringContainsBluetooth() {
        let conn = PrinterConnection.bluetoothMFi(id: "UUID-123")
        XCTAssertTrue(conn.displayString.contains("Bluetooth"))
    }

    // MARK: - PrinterKind raw values

    func test_printerKind_rawValues_areStable() {
        XCTAssertEqual(PrinterKind.thermalReceipt.rawValue, "thermalReceipt")
        XCTAssertEqual(PrinterKind.label.rawValue, "label")
        XCTAssertEqual(PrinterKind.documentAirPrint.rawValue, "documentAirPrint")
    }

    func test_printerKind_allCases_count() {
        XCTAssertEqual(PrinterKind.allCases.count, 3)
    }

    // MARK: - Helpers

    private static func makePrinter() -> Printer {
        Printer(
            id: "test",
            name: "Test Printer",
            kind: .thermalReceipt,
            connection: .network(host: "10.0.0.1", port: 9100)
        )
    }

    private static func makeReceiptJob() -> PrintJob {
        let payload = ReceiptPayload(
            tenantName: "Shop",
            tenantAddress: "1 St",
            tenantPhone: "555",
            receiptNumber: "R-1",
            createdAt: Date(timeIntervalSince1970: 0),
            lineItems: [.init(label: "Item", value: "$5.00")],
            subtotalCents: 500,
            taxCents: 40,
            tipCents: 0,
            totalCents: 540,
            paymentTender: "Cash",
            cashierName: "Alice"
        )
        return PrintJob(kind: .receipt, payload: .receipt(payload))
    }

    private static func makeLabelJob() -> PrintJob {
        let payload = LabelPayload(
            ticketNumber: "TKT-001",
            customerName: "Bob",
            deviceSummary: "iPhone 15",
            dateReceived: Date(timeIntervalSince1970: 0),
            qrContent: "qr://001",
            size: .small_2x1
        )
        return PrintJob(kind: .label, payload: .label(payload))
    }

    private static func makeTicketTagJob() -> PrintJob {
        let payload = TicketTagPayload(
            ticketNumber: "TKT-002",
            customerName: "Carol",
            deviceModel: "MacBook Air",
            promisedBy: nil,
            qrContent: "qr://002"
        )
        return PrintJob(kind: .ticketTag, payload: .ticketTag(payload))
    }

    private static func makeBarcodeJob() -> PrintJob {
        let payload = BarcodePayload(code: "12345678", format: .code128)
        return PrintJob(kind: .barcode, payload: .barcode(payload))
    }
}
