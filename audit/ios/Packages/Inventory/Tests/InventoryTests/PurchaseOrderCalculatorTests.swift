import XCTest
@testable import Inventory

final class PurchaseOrderCalculatorTests: XCTestCase {

    // MARK: - totalCents

    func test_totalCents_emptyLines_returnsZero() {
        XCTAssertEqual(PurchaseOrderCalculator.totalCents(lines: []), 0)
    }

    func test_totalCents_singleLine() {
        let line = makeLine(id: 1, qtyOrdered: 5, qtyReceived: 0, unitCostCents: 1000, lineTotalCents: 5000)
        XCTAssertEqual(PurchaseOrderCalculator.totalCents(lines: [line]), 5000)
    }

    func test_totalCents_multipleLines_sumsLineTotals() {
        let lines = [
            makeLine(id: 1, qtyOrdered: 2, qtyReceived: 0, unitCostCents: 500,  lineTotalCents: 1000),
            makeLine(id: 2, qtyOrdered: 3, qtyReceived: 0, unitCostCents: 800,  lineTotalCents: 2400),
            makeLine(id: 3, qtyOrdered: 1, qtyReceived: 0, unitCostCents: 1500, lineTotalCents: 1500)
        ]
        XCTAssertEqual(PurchaseOrderCalculator.totalCents(lines: lines), 4900)
    }

    func test_totalCents_usesLineTotalCentsNotComputed() {
        // lineTotalCents is pre-computed by server; calculator should use it as-is
        let line = makeLine(id: 1, qtyOrdered: 10, qtyReceived: 0, unitCostCents: 100, lineTotalCents: 999)
        XCTAssertEqual(PurchaseOrderCalculator.totalCents(lines: [line]), 999)
    }

    // MARK: - receivedProgress

    func test_receivedProgress_emptyPO_returnsZero() {
        let po = makePO(items: [])
        XCTAssertEqual(PurchaseOrderCalculator.receivedProgress(po: po), 0.0)
    }

    func test_receivedProgress_nothingReceived_returnsZero() {
        let po = makePO(items: [
            makeLine(id: 1, qtyOrdered: 10, qtyReceived: 0, unitCostCents: 100, lineTotalCents: 1000)
        ])
        XCTAssertEqual(PurchaseOrderCalculator.receivedProgress(po: po), 0.0)
    }

    func test_receivedProgress_fullyReceived_returnsOne() {
        let po = makePO(items: [
            makeLine(id: 1, qtyOrdered: 5, qtyReceived: 5, unitCostCents: 200, lineTotalCents: 1000),
            makeLine(id: 2, qtyOrdered: 3, qtyReceived: 3, unitCostCents: 300, lineTotalCents: 900)
        ])
        XCTAssertEqual(PurchaseOrderCalculator.receivedProgress(po: po), 1.0, accuracy: 0.001)
    }

    func test_receivedProgress_partiallyReceived() {
        let po = makePO(items: [
            makeLine(id: 1, qtyOrdered: 10, qtyReceived: 5, unitCostCents: 100, lineTotalCents: 1000)
        ])
        XCTAssertEqual(PurchaseOrderCalculator.receivedProgress(po: po), 0.5, accuracy: 0.001)
    }

    func test_receivedProgress_multiLinePartial() {
        let po = makePO(items: [
            makeLine(id: 1, qtyOrdered: 4, qtyReceived: 4, unitCostCents: 100, lineTotalCents: 400),
            makeLine(id: 2, qtyOrdered: 8, qtyReceived: 0, unitCostCents: 100, lineTotalCents: 800)
        ])
        // 4 received / 12 total = 0.333...
        XCTAssertEqual(PurchaseOrderCalculator.receivedProgress(po: po), 4.0 / 12.0, accuracy: 0.001)
    }

    func test_receivedProgress_overReceivedClampsToOne() {
        let po = makePO(items: [
            makeLine(id: 1, qtyOrdered: 5, qtyReceived: 10, unitCostCents: 100, lineTotalCents: 500)
        ])
        XCTAssertLessThanOrEqual(PurchaseOrderCalculator.receivedProgress(po: po), 1.0)
    }

    // MARK: - lineTotal

    func test_lineTotal_basic() {
        XCTAssertEqual(PurchaseOrderCalculator.lineTotal(unitCostCents: 250, qty: 4), 1000)
    }

    func test_lineTotal_zeroQty_returnsZero() {
        XCTAssertEqual(PurchaseOrderCalculator.lineTotal(unitCostCents: 999, qty: 0), 0)
    }

    func test_lineTotal_zeroUnit_returnsZero() {
        XCTAssertEqual(PurchaseOrderCalculator.lineTotal(unitCostCents: 0, qty: 100), 0)
    }

    // MARK: - Helpers

    private func makeLine(
        id: Int64,
        qtyOrdered: Int,
        qtyReceived: Int,
        unitCostCents: Int,
        lineTotalCents: Int
    ) -> POLineItem {
        POLineItem(
            id: id,
            sku: "SKU-\(id)",
            name: "Item \(id)",
            qtyOrdered: qtyOrdered,
            qtyReceived: qtyReceived,
            unitCostCents: unitCostCents,
            lineTotalCents: lineTotalCents
        )
    }

    private func makePO(items: [POLineItem]) -> PurchaseOrder {
        let total = PurchaseOrderCalculator.totalCents(lines: items)
        return PurchaseOrder(
            id: 1,
            supplierId: 42,
            status: .pending,
            createdAt: Date(),
            expectedDate: nil,
            items: items,
            totalCents: total,
            notes: nil
        )
    }
}
