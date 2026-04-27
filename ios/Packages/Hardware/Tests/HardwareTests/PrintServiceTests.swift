#if canImport(UIKit)
import XCTest
@testable import Hardware

// MARK: - PrintServiceTests
//
// §17 PrintService: queue, retries, toast, fallback, offline.

@MainActor
final class PrintServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makePrintJob() -> PrintJob {
        PrintJob(
            kind: .receipt,
            payload: .receipt(ReceiptPayload.stub())
        )
    }

    // MARK: - Toast message

    func test_submit_withNoPrinterConfigured_setsToastMessage() async {
        let mockEngine = MockPrinter()
        let store = PrinterProfileStore()
        let service = PrintService(engine: mockEngine, settings: store)

        // No printer configured — fallback path (no presenter → toast only)
        let result = await service.submit(makePrintJob())
        XCTAssertTrue(result)
        // Toast should mention "No printer" or "share PDF"
        XCTAssertNotNil(service.toastMessage)
    }

    func test_submit_withMockPrinter_doesNotCrash() async throws {
        let mockEngine = MockPrinter()
        let store = PrinterProfileStore()

        // Register a fake printer in the catalogue
        let fakePrinter = Printer(
            id: "test-printer-1",
            name: "Test Printer",
            kind: .thermalReceipt,
            connection: .network(host: "192.168.1.100", port: 9100)
        )
        store.persist(printer: fakePrinter)

        // Patch the current profile's defaultReceiptPrinterId
        var profile = store.currentProfile
        let patchedProfile = PrinterProfile(
            stationId: profile.stationId,
            stationName: profile.stationName,
            locationId: profile.locationId,
            defaultReceiptPrinterId: "test-printer-1",
            defaultLabelPrinterId: profile.defaultLabelPrinterId,
            paperSize: profile.paperSize
        )
        store.save(patchedProfile)

        let service = PrintService(engine: mockEngine, settings: store)
        let result = await service.submit(makePrintJob())
        XCTAssertTrue(result)
    }

    // MARK: - drainQueue

    func test_drainQueue_withNoPendingJobs_isNoOp() async {
        let service = PrintService(engine: MockPrinter(), settings: PrinterProfileStore())
        XCTAssertEqual(service.pendingCount, 0)
        await service.drainQueue()
        XCTAssertEqual(service.pendingCount, 0)
    }

    // MARK: - isPrinting state

    func test_isPrinting_initiallyFalse() {
        let service = PrintService(engine: MockPrinter(), settings: PrinterProfileStore())
        XCTAssertFalse(service.isPrinting)
    }

    // MARK: - PrintService fallback PDF data (private path via no-presenter)

    func test_submit_noPrinterNoPresenter_returnsTrueAndSetToast() async {
        let service = PrintService(engine: MockPrinter(), settings: PrinterProfileStore())
        let result = await service.submit(makePrintJob(), previewImage: nil, presenter: nil)
        XCTAssertTrue(result)
        XCTAssertNotNil(service.toastMessage)
    }
}

// MARK: - ReceiptPayload stub for tests

private extension ReceiptPayload {
    static func stub() -> ReceiptPayload {
        ReceiptPayload(
            tenantName: "Test Shop",
            tenantAddress: "123 Main St",
            tenantPhone: "555-1234",
            receiptNumber: "R-001",
            createdAt: Date(),
            lineItems: [.init(label: "Widget", value: "$9.99")],
            subtotalCents: 999,
            taxCents: 0,
            tipCents: 0,
            totalCents: 999,
            paymentTender: "Cash",
            cashierName: "Test"
        )
    }
}

#endif
