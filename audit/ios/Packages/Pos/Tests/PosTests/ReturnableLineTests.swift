#if canImport(UIKit)
import XCTest
@testable import Pos

/// §16.9 — Unit tests for `ReturnableLine` model and `PosReturnSummaryBar` logic.
/// No network, no DB.
final class ReturnableLineTests: XCTestCase {

    // MARK: - ReturnableLine init / normalization

    func test_init_setsFields() {
        let line = ReturnableLine(id: 1, description: "Widget", originalQty: 3, unitPriceCents: 500)
        XCTAssertEqual(line.id, 1)
        XCTAssertEqual(line.description, "Widget")
        XCTAssertEqual(line.originalQty, 3)
        XCTAssertEqual(line.unitPriceCents, 500)
        XCTAssertFalse(line.isSelected)
        XCTAssertTrue(line.restock)
    }

    func test_init_negativeQty_clampsToOne() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: -2, unitPriceCents: 100)
        XCTAssertEqual(line.originalQty, 1)
    }

    func test_init_zeroQty_clampsToOne() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 0, unitPriceCents: 100)
        XCTAssertEqual(line.originalQty, 1)
    }

    func test_init_negativePriceCents_clampsToZero() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 1, unitPriceCents: -50)
        XCTAssertEqual(line.unitPriceCents, 0)
    }

    func test_init_qtyToReturnDefaultsToOriginalQty() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 5, unitPriceCents: 100)
        XCTAssertEqual(line.qtyToReturn, 5)
    }

    func test_init_qtyToReturnClampsToOriginalQty() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 3, unitPriceCents: 100, qtyToReturn: 10)
        XCTAssertEqual(line.qtyToReturn, 3)
    }

    // MARK: - refundCents

    func test_refundCents_singleUnit() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 1, unitPriceCents: 999)
        XCTAssertEqual(line.refundCents, 999)
    }

    func test_refundCents_multipleQty() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 3, unitPriceCents: 500, qtyToReturn: 2)
        XCTAssertEqual(line.refundCents, 1000)
    }

    func test_refundCents_zeroPriceCents() {
        let line = ReturnableLine(id: 1, description: "X", originalQty: 5, unitPriceCents: 0)
        XCTAssertEqual(line.refundCents, 0)
    }

    // MARK: - from(invoiceLines:)

    func test_fromInvoiceLines_mapsCorrectly() {
        let invoiceLines = [
            InvoiceLineItem(id: 1, name: "A", description: nil, qty: 2, unitPriceCents: 300),
            InvoiceLineItem(id: 2, name: nil, description: "B desc", qty: 1, unitPriceCents: 100),
        ]
        let lines = ReturnableLine.from(invoiceLines: invoiceLines)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].description, "A")
        XCTAssertEqual(lines[1].description, "B desc")
        XCTAssertEqual(lines[0].originalQty, 2)
        XCTAssertEqual(lines[0].unitPriceCents, 300)
    }

    func test_fromInvoiceLines_allStartUnselected() {
        let invoiceLines = [
            InvoiceLineItem(id: 1, name: "A", description: nil, qty: 1, unitPriceCents: 100)
        ]
        let lines = ReturnableLine.from(invoiceLines: invoiceLines)
        XCTAssertFalse(lines[0].isSelected)
    }

    func test_fromInvoiceLines_fallsBackToDescription() {
        let item = InvoiceLineItem(id: 1, name: nil, description: nil, qty: 1, unitPriceCents: 100)
        let lines = ReturnableLine.from(invoiceLines: [item])
        XCTAssertEqual(lines[0].description, "Item")
    }

    // MARK: - PosReturnSummaryBar logic

    func test_summaryBar_totalRefundCents_sumSelectedLines() {
        let lines = [
            ReturnableLine(id: 1, description: "A", originalQty: 1, unitPriceCents: 500, isSelected: true),
            ReturnableLine(id: 2, description: "B", originalQty: 1, unitPriceCents: 300, isSelected: true),
            ReturnableLine(id: 3, description: "C", originalQty: 1, unitPriceCents: 200, isSelected: false),
        ]
        let bar = PosReturnSummaryBar(selectedLines: lines)
        XCTAssertEqual(bar.totalRefundCents, 800)
    }

    func test_summaryBar_requiresManagerPin_aboveThreshold() {
        let line = ReturnableLine(id: 1, description: "A", originalQty: 1, unitPriceCents: 6000, isSelected: true)
        let bar = PosReturnSummaryBar(selectedLines: [line], managerPinThresholdCents: 5000)
        XCTAssertTrue(bar.requiresManagerPin)
    }

    func test_summaryBar_requiresManagerPin_belowThreshold() {
        let line = ReturnableLine(id: 1, description: "A", originalQty: 1, unitPriceCents: 4999, isSelected: true)
        let bar = PosReturnSummaryBar(selectedLines: [line], managerPinThresholdCents: 5000)
        XCTAssertFalse(bar.requiresManagerPin)
    }

    func test_summaryBar_noSelectedLines_totalZero() {
        let lines = [
            ReturnableLine(id: 1, description: "A", originalQty: 1, unitPriceCents: 500, isSelected: false)
        ]
        let bar = PosReturnSummaryBar(selectedLines: lines)
        XCTAssertEqual(bar.totalRefundCents, 0)
    }

    // MARK: - InvoiceLineItem decoding

    func test_invoiceLineItem_decodesFromJSON() throws {
        let json = """
        {
          "id": 42,
          "name": "Test Item",
          "qty": 3,
          "unit_price": 12.99
        }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(InvoiceLineItem.self, from: json)
        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.name, "Test Item")
        XCTAssertEqual(item.qty, 3)
        XCTAssertEqual(item.unitPriceCents, 1299)
    }

    func test_invoiceLineItem_decodesMissingQty_defaultsToOne() throws {
        let json = """
        { "id": 1, "unit_price": 5.00 }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(InvoiceLineItem.self, from: json)
        XCTAssertEqual(item.qty, 1)
    }
}
#endif
