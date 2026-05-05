import XCTest
@testable import Pos

/// §39.4 — Unit tests for `ReconciliationCSVGenerator` and `ReconciliationRow`.
/// No UIKit. No network. Pure logic.
final class ReconciliationCSVGeneratorTests: XCTestCase {

    private let sut = ReconciliationCSVGenerator()

    // MARK: - Filename

    func test_filename_containsDate() {
        let date = Date(timeIntervalSince1970: 0)  // 1970-01-01
        let name = sut.filename(for: date)
        XCTAssertTrue(name.hasPrefix("Reconciliation-1970-01-01"), name)
        XCTAssertTrue(name.hasSuffix(".csv"), name)
    }

    func test_filename_defaultUsesToday() {
        let name = sut.filename()
        XCTAssertTrue(name.hasPrefix("Reconciliation-"))
        XCTAssertTrue(name.hasSuffix(".csv"))
    }

    // MARK: - Header

    func test_generate_emptyTransactions_producesHeaderOnly() {
        let csv = sut.generate(transactions: [])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].hasPrefix("date_time,invoice_id"))
    }

    func test_header_containsAllExpectedColumns() {
        let csv = sut.generate(transactions: [])
        let header = csv.components(separatedBy: "\n")[0]
        let expected = [
            "date_time", "invoice_id", "line_description", "qty",
            "unit_price_cents", "line_total_cents", "tender_method",
            "tender_amount_cents", "cashier_id", "session_id", "notes"
        ]
        for col in expected {
            XCTAssertTrue(header.contains(col), "Header missing: \(col)")
        }
    }

    // MARK: - Row output

    func test_generate_singleRow_twoLines() {
        let row = makeRow()
        let csv = sut.generate(transactions: [row])
        let lines = csv.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
    }

    func test_generate_rowContainsInvoiceId() {
        let row = makeRow(invoiceId: 9999)
        let csv = sut.generate(transactions: [row])
        XCTAssertTrue(csv.contains("9999"))
    }

    func test_generate_rowContainsTenderMethod() {
        let row = makeRow(tenderMethod: "card")
        let csv = sut.generate(transactions: [row])
        XCTAssertTrue(csv.contains("card"))
    }

    func test_generate_nilCashierId_emptyField() {
        let row = makeRow(cashierId: nil)
        let csv = sut.generate(transactions: [row])
        // nil cashier_id renders as empty (two consecutive commas)
        XCTAssertTrue(csv.contains(",,"))
    }

    func test_generate_optionalNotes_emptyString() {
        let row = makeRow(notes: nil)
        let csv = sut.generate(transactions: [row])
        // ends with empty notes field
        let dataLine = csv.components(separatedBy: "\n")[1]
        XCTAssertTrue(dataLine.hasSuffix(","))
    }

    // MARK: - csvEscape

    func test_csvEscape_plainString_noQuotes() {
        XCTAssertEqual(ReconciliationRow.csvEscape("hello"), "hello")
    }

    func test_csvEscape_stringWithComma_wrapsInQuotes() {
        XCTAssertEqual(ReconciliationRow.csvEscape("a,b"), "\"a,b\"")
    }

    func test_csvEscape_stringWithQuote_doublesQuote() {
        XCTAssertEqual(ReconciliationRow.csvEscape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func test_csvEscape_stringWithNewline_wrapsInQuotes() {
        let result = ReconciliationRow.csvEscape("line1\nline2")
        XCTAssertTrue(result.hasPrefix("\""))
        XCTAssertTrue(result.hasSuffix("\""))
    }

    func test_csvEscape_emptyString_noQuotes() {
        XCTAssertEqual(ReconciliationRow.csvEscape(""), "")
    }

    // MARK: - Helpers

    private func makeRow(
        invoiceId: Int64 = 1,
        tenderMethod: String = "cash",
        cashierId: Int64? = 10,
        notes: String? = "test note"
    ) -> ReconciliationRow {
        ReconciliationRow(
            dateTime: Date(timeIntervalSince1970: 1_000_000),
            invoiceId: invoiceId,
            lineDescription: "Widget",
            qty: 2,
            unitPriceCents: 500,
            lineTotalCents: 1000,
            tenderMethod: tenderMethod,
            tenderAmountCents: 1000,
            cashierId: cashierId,
            sessionId: 5,
            notes: notes
        )
    }
}
