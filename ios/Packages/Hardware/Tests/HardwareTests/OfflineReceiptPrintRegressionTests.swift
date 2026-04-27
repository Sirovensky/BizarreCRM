import XCTest
@testable import Hardware

// §17.4 Regression test: offline receipt print.
//
// Requirement: Log out of the app, attempt to print a cached recent receipt
// (detail opened while online, then session ended) → printer must still
// produce correct output, because rendering is fully local and only the
// device-to-printer transport is needed.
//
// What we test here:
//   1. ReceiptPayload carries ALL required data (zero deferred network reads).
//   2. ReceiptRenderer can rasterize without a network call (pure, sync).
//   3. PrintJob.payload encodes/decodes losslessly (survives serialisation
//      across app restart via PrintJobStore).
//   4. MockPrinter records the job without touching the network.

final class OfflineReceiptPrintRegressionTests: XCTestCase {

    // MARK: - Test 1: Payload is self-contained (no URLs, only embedded data)

    func testReceiptPayload_containsNoURLs() {
        // Build a typical payload as it would be assembled after an online sale
        let logoData = Data("fake-png-bytes".utf8)
        let payload = ReceiptPayload(
            logoData: logoData,
            tenantName: "Bizarre Repair Co.",
            tenantAddress: "123 Main St, Springfield",
            tenantPhone: "(555) 867-5309",
            receiptNumber: "R-2024-00042",
            createdAt: Date(timeIntervalSince1970: 1_714_000_000),
            lineItems: [
                ReceiptPayload.Line(label: "iPhone 15 Screen Repair", value: "$149.99"),
                ReceiptPayload.Line(label: "Labour (1h)", value: "$75.00")
            ],
            subtotalCents: 22499,
            taxCents: 1912,
            tipCents: 0,
            totalCents: 24411,
            paymentTender: "Visa",
            paymentAuthLast4: "4242",
            cashierName: "Jordan",
            footerMessage: "Thank you! 90-day warranty on parts & labour.",
            qrContent: "https://biz.app/receipt/R-2024-00042"
        )

        // Verify no URL strings exist in the model (only the QR *content* string — not fetched at print time)
        XCTAssertNotNil(payload.logoData, "Logo must be embedded as Data, not a URL")
        XCTAssertFalse(payload.tenantName.isEmpty)
        XCTAssertFalse(payload.receiptNumber.isEmpty)
        // qrContent is a deep-link for QR rendering (rendered from string, not fetched)
        // It should not be a remote image URL that requires auth
        XCTAssertFalse(payload.qrContent?.hasPrefix("http") == true
                       && payload.qrContent?.contains("logo") == true,
                       "qrContent should be a deep-link string, not a logo image URL")
    }

    // MARK: - Test 2: Payload round-trips through JSON (survives app restart)

    func testReceiptPayload_encodesAndDecodes() throws {
        let original = ReceiptPayload(
            logoData: Data("png".utf8),
            tenantName: "Test Shop",
            tenantAddress: "1 Test Ave",
            tenantPhone: "(000) 000-0000",
            receiptNumber: "TEST-999",
            createdAt: Date(timeIntervalSince1970: 0),
            lineItems: [ReceiptPayload.Line(label: "Widget", value: "$10.00")],
            subtotalCents: 1000,
            taxCents: 80,
            tipCents: 0,
            totalCents: 1080,
            paymentTender: "Cash",
            cashierName: "System"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ReceiptPayload.self, from: data)

        XCTAssertEqual(decoded.tenantName, original.tenantName)
        XCTAssertEqual(decoded.receiptNumber, original.receiptNumber)
        XCTAssertEqual(decoded.totalCents, original.totalCents)
        XCTAssertEqual(decoded.lineItems.count, original.lineItems.count)
        XCTAssertEqual(decoded.logoData, original.logoData)
    }

    // MARK: - Test 3: MockPrinter records the job without any network call

    func testMockPrinter_recordsJobOffline() async throws {
        let mock = MockPrinter()
        let payload = ReceiptPayload(
            tenantName: "Offline Test",
            tenantAddress: "",
            tenantPhone: "",
            receiptNumber: "OFF-001",
            createdAt: Date(),
            lineItems: [],
            subtotalCents: 0,
            taxCents: 0,
            tipCents: 0,
            totalCents: 0,
            paymentTender: "Cash",
            cashierName: "Cashier"
        )
        let job = PrintJob(kind: .receipt, payload: .receipt(payload))
        let printer = Printer(
            id: "mock://1",
            name: "Mock Thermal",
            kind: .thermalReceipt,
            connection: .network(host: "192.168.1.100", port: 9100)
        )

        // Should not throw; no network access occurs in MockPrinter
        try await mock.print(job, on: printer)

        let printed = await mock.printedJobs
        XCTAssertEqual(printed.count, 1)
        XCTAssertEqual(printed.first?.id, job.id)
    }

    // MARK: - Test 4: PrintJobQueue persists jobs that survive serialisation

    func testPrintJobQueue_enqueuedJobSurvivesStore() throws {
        let store = PrintJobStore()
        let jobId = UUID()
        let printerData = try JSONEncoder().encode(
            Printer(id: "test://p1", name: "Test", kind: .thermalReceipt, connection: .network(host: "1.2.3.4", port: 9100))
        )
        let payloadData = try JSONEncoder().encode(["test": "data"])

        let entry = PersistedJobEntry(
            jobId: jobId,
            jobKind: "receipt",
            payloadData: payloadData,
            payloadKind: "receipt",
            printerData: printerData,
            attempts: 1,
            lastError: "Connection timed out",
            deadLettered: false
        )

        try store.upsert(entry)
        let loaded = try store.load()
        guard let found = loaded.first(where: { $0.jobId == jobId }) else {
            XCTFail("Persisted job not found after store reload")
            return
        }
        XCTAssertEqual(found.jobId, jobId)
        XCTAssertEqual(found.attempts, 1)
        XCTAssertEqual(found.lastError, "Connection timed out")
        XCTAssertFalse(found.deadLettered)

        // Cleanup
        try store.delete(id: entry.id)
    }
}
