#if canImport(UIKit)
import XCTest
@testable import Hardware

// MARK: - PrintServiceTests
//
// §17 PrintService: queue, retries, toast, fallback, offline, submitWithOptions.

// MARK: - PrintEngine mock (local to this test file)

private final class SpyPrintEngine: PrintEngine, @unchecked Sendable {
    var printCallCount: Int = 0
    var lastJob: PrintJob?
    var shouldThrow: Bool = false

    func discover() async throws -> [Printer] { [] }

    func print(_ job: PrintJob, on printer: Printer) async throws {
        printCallCount += 1
        lastJob = job
        if shouldThrow {
            throw PrintEngineError.printerNotReachable("spy-mock")
        }
    }
}

@MainActor
final class PrintServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makePrintJob(copies: Int = 1) -> PrintJob {
        PrintJob(
            kind: .receipt,
            payload: .receipt(ReceiptPayload.stub()),
            copies: copies
        )
    }

    private func makeServiceWithPrinter(
        printerId: String = "test-printer-1",
        engine: any PrintEngine
    ) -> (PrintService, Printer, PrinterProfileStore) {
        let store = PrinterProfileStore()
        let fakePrinter = Printer(
            id: printerId,
            name: "Test Printer",
            kind: .thermalReceipt,
            connection: .network(host: "192.168.1.100", port: 9100)
        )
        store.persist(printer: fakePrinter)
        let profile = store.currentProfile
        let patchedProfile = PrinterProfile(
            stationId: profile.stationId,
            stationName: profile.stationName,
            locationId: profile.locationId,
            defaultReceiptPrinterId: printerId,
            defaultLabelPrinterId: profile.defaultLabelPrinterId,
            paperSize: profile.paperSize
        )
        store.save(patchedProfile)
        let service = PrintService(engine: engine, settings: store)
        return (service, fakePrinter, store)
    }

    // MARK: - Basic submit (no printer configured)

    func test_submit_withNoPrinterConfigured_setsToastMessage() async {
        let engine = SpyPrintEngine()
        let service = PrintService(engine: engine, settings: PrinterProfileStore())
        let result = await service.submit(makePrintJob())
        XCTAssertTrue(result)
        XCTAssertNotNil(service.toastMessage)
    }

    func test_submit_withMockPrinter_doesNotCrash() async throws {
        let engine = SpyPrintEngine()
        let (service, _, _) = makeServiceWithPrinter(engine: engine)
        let result = await service.submit(makePrintJob())
        XCTAssertTrue(result)
    }

    // MARK: - drainQueue

    func test_drainQueue_withNoPendingJobs_isNoOp() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        XCTAssertEqual(service.pendingCount, 0)
        await service.drainQueue()
        XCTAssertEqual(service.pendingCount, 0)
    }

    // MARK: - isPrinting state

    func test_isPrinting_initiallyFalse() {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        XCTAssertFalse(service.isPrinting)
    }

    // MARK: - Fallback (no printer, no presenter)

    func test_submit_noPrinterNoPresenter_returnsTrueAndSetToast() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        let result = await service.submit(makePrintJob(), previewImage: nil, presenter: nil)
        XCTAssertTrue(result)
        XCTAssertNotNil(service.toastMessage)
    }

    // MARK: - submitWithOptions: no printer → fallback

    func test_submitWithOptions_noPrinterNoPresenter_returnsTrueAndSetToast() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        let options = PrintOptions(
            selectedPrinter: nil,
            paperSize: .thermal80mm,
            copies: 1
        )
        let result = await service.submitWithOptions(makePrintJob(), options: options)
        XCTAssertTrue(result)
        XCTAssertNotNil(service.toastMessage)
    }

    // MARK: - submitWithOptions: copies

    func test_submitWithOptions_2copies_sendsJobTwice() async {
        let engine = SpyPrintEngine()
        let (service, fakePrinter, _) = makeServiceWithPrinter(printerId: "opts-printer", engine: engine)
        let options = PrintOptions(
            selectedPrinter: fakePrinter,
            paperSize: .thermal80mm,
            copies: 2
        )
        let result = await service.submitWithOptions(makePrintJob(), options: options)
        XCTAssertTrue(result)
        XCTAssertEqual(engine.printCallCount, 2)
    }

    func test_submitWithOptions_1copy_sendsJobOnce() async {
        let engine = SpyPrintEngine()
        let (service, fakePrinter, _) = makeServiceWithPrinter(printerId: "one-copy", engine: engine)
        let options = PrintOptions(
            selectedPrinter: fakePrinter,
            paperSize: .letter,
            copies: 1
        )
        let result = await service.submitWithOptions(makePrintJob(), options: options)
        XCTAssertTrue(result)
        XCTAssertEqual(engine.printCallCount, 1)
    }

    // MARK: - submitWithOptions: audit logger

    func test_submitWithOptions_firesAuditLoggerWithCorrectArgs() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        let options = PrintOptions(
            selectedPrinter: nil,
            paperSize: .thermal80mm,
            copies: 1,
            reason: .accountantRequest
        )
        var capturedKind: String?
        var capturedId: Int64?
        var capturedReason: String?
        var capturedDoc: String?

        let result = await service.submitWithOptions(
            makePrintJob(),
            options: options,
            auditLogger: { kind, id, reason, doc in
                capturedKind = kind
                capturedId = id
                capturedReason = reason
                capturedDoc = doc
            },
            entityKind: "sale",
            entityId: 42
        )
        XCTAssertTrue(result)
        XCTAssertEqual(capturedKind, "sale")
        XCTAssertEqual(capturedId, 42)
        XCTAssertEqual(capturedReason, ReprintReason.accountantRequest.rawValue)
        XCTAssertNotNil(capturedDoc)
    }

    func test_submitWithOptions_skipsAuditWhenEntityIdIsZero() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        let options = PrintOptions(selectedPrinter: nil, paperSize: .thermal80mm, copies: 1)
        var auditFired = false
        _ = await service.submitWithOptions(
            makePrintJob(),
            options: options,
            auditLogger: { _, _, _, _ in auditFired = true },
            entityId: 0
        )
        XCTAssertFalse(auditFired)
    }

    func test_submitWithOptions_skipsAuditWhenNoLoggerProvided() async {
        let engine = SpyPrintEngine()
        let (service, fakePrinter, _) = makeServiceWithPrinter(engine: engine)
        let options = PrintOptions(
            selectedPrinter: fakePrinter,
            paperSize: .thermal80mm,
            copies: 1,
            reason: .customerLostIt
        )
        // No auditLogger provided — should not crash and should still print.
        let result = await service.submitWithOptions(makePrintJob(), options: options)
        XCTAssertTrue(result)
        XCTAssertEqual(engine.printCallCount, 1)
    }

    // MARK: - PrintJob copies clamping

    func test_printJob_clampsCopiesTo1WhenZero() {
        let job = PrintJob(kind: .receipt, payload: .receipt(ReceiptPayload.stub()), copies: 0)
        XCTAssertEqual(job.copies, 1)
    }

    func test_printJob_clampsCopiesTo1WhenNegative() {
        let job = PrintJob(kind: .receipt, payload: .receipt(ReceiptPayload.stub()), copies: -3)
        XCTAssertEqual(job.copies, 1)
    }

    func test_printJob_copiesStoredWhenPositive() {
        let job = PrintJob(kind: .receipt, payload: .receipt(ReceiptPayload.stub()), copies: 5)
        XCTAssertEqual(job.copies, 5)
    }

    func test_printJob_defaultCopiesIs1() {
        let job = PrintJob(kind: .receipt, payload: .receipt(ReceiptPayload.stub()))
        XCTAssertEqual(job.copies, 1)
    }

    // MARK: - retryDeadLetter

    func test_retryDeadLetter_withNoPrinter_setsToast() async {
        let service = PrintService(engine: SpyPrintEngine(), settings: PrinterProfileStore())
        await service.retryDeadLetter(id: UUID())
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
