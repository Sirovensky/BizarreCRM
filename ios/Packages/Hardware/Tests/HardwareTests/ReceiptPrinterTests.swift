import XCTest
@testable import Hardware

final class ReceiptPrinterTests: XCTestCase {

    // A freshly-constructed NullReceiptPrinter must always report
    // `isAvailable() == false` — it's the "no hardware paired" fallback
    // and UI callers branch on that to show the pairing banner.
    func test_nullPrinter_isAvailable_false() {
        let printer = NullReceiptPrinter()
        XCTAssertFalse(printer.isAvailable())
    }

    // Both mutating methods (printReceipt, openCashDrawer) must throw
    // `.notPaired` — never silently succeed. Silent success would mask
    // a missing hardware configuration.
    func test_nullPrinter_mutations_throwNotPaired() async {
        let printer = NullReceiptPrinter()
        let payload = ReceiptPayload(
            lines: ["Line 1"],
            totalCents: 1234,
            merchant: "Bizarre CRM",
            date: Date(timeIntervalSince1970: 0)
        )

        do {
            try await printer.printReceipt(payload)
            XCTFail("Expected notPaired error when printing on a null printer")
        } catch let error as ReceiptPrinterError {
            XCTAssertEqual(error, .notPaired)
        } catch {
            XCTFail("Expected ReceiptPrinterError.notPaired but got \(error)")
        }

        do {
            try await printer.openCashDrawer()
            XCTFail("Expected notPaired error when opening drawer on a null printer")
        } catch let error as ReceiptPrinterError {
            XCTAssertEqual(error, .notPaired)
        } catch {
            XCTFail("Expected ReceiptPrinterError.notPaired but got \(error)")
        }
    }

    // Error descriptions are surfaced in UI ("Pair a printer in Settings"
    // banner), so regressing these strings is a visible bug.
    func test_errorDescriptions_arePopulated() {
        XCTAssertNotNil(ReceiptPrinterError.notPaired.errorDescription)
        XCTAssertTrue(ReceiptPrinterError.notPaired.errorDescription!.contains("not paired"))
        XCTAssertNotNil(ReceiptPrinterError.notAvailable.errorDescription)
        XCTAssertNotNil(ReceiptPrinterError.printFailed("boom").errorDescription)
        XCTAssertTrue(ReceiptPrinterError.printFailed("boom").errorDescription!.contains("boom"))
        XCTAssertNotNil(ReceiptPrinterError.drawerFailed("stuck").errorDescription)
    }
}
