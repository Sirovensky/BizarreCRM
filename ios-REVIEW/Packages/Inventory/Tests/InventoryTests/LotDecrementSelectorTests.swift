import XCTest
@testable import Inventory

final class LotDecrementSelectorTests: XCTestCase {

    // MARK: - Helpers

    private func lot(
        id: Int64,
        qty: Int,
        receiveDate: String = "2026-01-01T00:00:00Z",
        expiry: String? = nil
    ) -> InventoryLot {
        let json = """
        {
          "id": \(id),
          "parent_sku": "SKU001",
          "lot_id": "LOT-\(id)",
          "receive_date": "\(receiveDate)",
          "vendor_invoice": null,
          "qty": \(qty),
          "expiry": \(expiry.map { "\"\($0)\"" } ?? "null")
        }
        """
        return try! JSONDecoder().decode(InventoryLot.self, from: json.data(using: .utf8)!)
    }

    // MARK: - FIFO

    func test_fifo_selectsOldestFirst() {
        let lots = [
            lot(id: 1, qty: 10, receiveDate: "2026-03-01T00:00:00Z"),
            lot(id: 2, qty: 10, receiveDate: "2026-01-01T00:00:00Z"),
            lot(id: 3, qty: 10, receiveDate: "2026-02-01T00:00:00Z")
        ]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 5, policy: .fifo)
        XCTAssertEqual(result.first?.lotId, "LOT-2")  // Jan is oldest
    }

    func test_fifo_spansMultipleLots() {
        let lots = [
            lot(id: 1, qty: 3, receiveDate: "2026-01-01T00:00:00Z"),
            lot(id: 2, qty: 10, receiveDate: "2026-02-01T00:00:00Z")
        ]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 7, policy: .fifo)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].qty, 3)  // exhaust lot 1
        XCTAssertEqual(result[1].qty, 4)  // take remainder from lot 2
    }

    // MARK: - LIFO

    func test_lifo_selectsNewestFirst() {
        let lots = [
            lot(id: 1, qty: 10, receiveDate: "2026-01-01T00:00:00Z"),
            lot(id: 2, qty: 10, receiveDate: "2026-03-01T00:00:00Z")
        ]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 5, policy: .lifo)
        XCTAssertEqual(result.first?.lotId, "LOT-2")  // March is newest
    }

    // MARK: - FEFO

    func test_fefo_selectsEarliestExpiryFirst() {
        let lots = [
            lot(id: 1, qty: 10, receiveDate: "2026-01-01T00:00:00Z", expiry: "2027-12-31T00:00:00Z"),
            lot(id: 2, qty: 10, receiveDate: "2026-01-01T00:00:00Z", expiry: "2026-06-01T00:00:00Z")
        ]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 5, policy: .fefo)
        XCTAssertEqual(result.first?.lotId, "LOT-2")  // Jun expires before Dec
    }

    func test_fefo_nilExpiryGoesLast() {
        let lots = [
            lot(id: 1, qty: 10, receiveDate: "2026-01-01T00:00:00Z", expiry: nil),
            lot(id: 2, qty: 10, receiveDate: "2026-01-01T00:00:00Z", expiry: "2026-06-01T00:00:00Z")
        ]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 5, policy: .fefo)
        XCTAssertEqual(result.first?.lotId, "LOT-2")  // expiring lot first
    }

    // MARK: - Edge cases

    func test_emptyLots_returnsEmpty() {
        let result = LotDecrementSelector.selectLots(from: [], qty: 5, policy: .fifo)
        XCTAssertTrue(result.isEmpty)
    }

    func test_qtyZero_returnsEmpty() {
        let lots = [lot(id: 1, qty: 10)]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 0, policy: .fifo)
        XCTAssertTrue(result.isEmpty)
    }

    func test_qtyMoreThanAvailable_exhaustsAllLots() {
        let lots = [lot(id: 1, qty: 3), lot(id: 2, qty: 2)]
        let result = LotDecrementSelector.selectLots(from: lots, qty: 100, policy: .fifo)
        XCTAssertEqual(result.reduce(0) { $0 + $1.qty }, 5)  // only 5 available
    }

    // MARK: - InventoryLot expiry checks

    func test_lot_isExpired_pastDate() {
        let l = lot(id: 1, qty: 5, expiry: "2020-01-01T00:00:00Z")
        XCTAssertTrue(l.isExpired)
    }

    func test_lot_notExpired_futureDate() {
        let l = lot(id: 1, qty: 5, expiry: "2099-01-01T00:00:00Z")
        XCTAssertFalse(l.isExpired)
    }

    func test_lot_isNearExpiry_within30days() {
        let nearFuture = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(15 * 86400)
        )
        let l = lot(id: 1, qty: 5, expiry: nearFuture)
        XCTAssertTrue(l.isNearExpiry)
    }
}
