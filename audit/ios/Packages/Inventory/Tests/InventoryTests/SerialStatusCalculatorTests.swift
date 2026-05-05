import XCTest
@testable import Inventory

final class SerialStatusCalculatorTests: XCTestCase {

    // MARK: - statusCounts

    func test_statusCounts_empty_returnsEmpty() {
        XCTAssertTrue(SerialStatusCalculator.statusCounts(for: []).isEmpty)
    }

    func test_statusCounts_singleSKU_correctCounts() {
        let items = [
            makeSerial(id: 1, sku: "IPH-001", status: .available),
            makeSerial(id: 2, sku: "IPH-001", status: .available),
            makeSerial(id: 3, sku: "IPH-001", status: .sold),
            makeSerial(id: 4, sku: "IPH-001", status: .reserved)
        ]
        let counts = SerialStatusCalculator.statusCounts(for: items)
        XCTAssertEqual(counts.count, 1)
        let c = counts[0]
        XCTAssertEqual(c.sku, "IPH-001")
        XCTAssertEqual(c.available, 2)
        XCTAssertEqual(c.sold, 1)
        XCTAssertEqual(c.reserved, 1)
        XCTAssertEqual(c.returned, 0)
        XCTAssertEqual(c.total, 4)
    }

    func test_statusCounts_multiSKU_groupedCorrectly() {
        let items = [
            makeSerial(id: 1, sku: "A-001", status: .available),
            makeSerial(id: 2, sku: "B-001", status: .sold),
            makeSerial(id: 3, sku: "A-001", status: .returned)
        ]
        let counts = SerialStatusCalculator.statusCounts(for: items)
        XCTAssertEqual(counts.count, 2)
        let a = counts.first(where: { $0.sku == "A-001" })!
        let b = counts.first(where: { $0.sku == "B-001" })!
        XCTAssertEqual(a.available, 1)
        XCTAssertEqual(a.returned, 1)
        XCTAssertEqual(b.sold, 1)
    }

    func test_statusCounts_sortedBySKU() {
        let items = [
            makeSerial(id: 1, sku: "Z-SKU", status: .available),
            makeSerial(id: 2, sku: "A-SKU", status: .sold)
        ]
        let counts = SerialStatusCalculator.statusCounts(for: items)
        XCTAssertEqual(counts[0].sku, "A-SKU")
        XCTAssertEqual(counts[1].sku, "Z-SKU")
    }

    // MARK: - counts (single SKU)

    func test_counts_allStatuses() {
        let items = [
            makeSerial(id: 1, sku: "X", status: .available),
            makeSerial(id: 2, sku: "X", status: .reserved),
            makeSerial(id: 3, sku: "X", status: .sold),
            makeSerial(id: 4, sku: "X", status: .returned)
        ]
        let c = SerialStatusCalculator.counts(sku: "X", serials: items)
        XCTAssertEqual(c.available, 1)
        XCTAssertEqual(c.reserved, 1)
        XCTAssertEqual(c.sold, 1)
        XCTAssertEqual(c.returned, 1)
        XCTAssertEqual(c.total, 4)
    }

    func test_counts_empty() {
        let c = SerialStatusCalculator.counts(sku: "EMPTY", serials: [])
        XCTAssertEqual(c.total, 0)
    }

    // MARK: - availableUnits

    func test_availableUnits_filtersCorrectly() {
        let items = [
            makeSerial(id: 1, sku: "SKU-A", status: .available),
            makeSerial(id: 2, sku: "SKU-A", status: .sold),
            makeSerial(id: 3, sku: "SKU-A", status: .available),
            makeSerial(id: 4, sku: "SKU-B", status: .available)  // wrong SKU
        ]
        let available = SerialStatusCalculator.availableUnits(from: items, sku: "SKU-A")
        XCTAssertEqual(available.count, 2)
        XCTAssertTrue(available.allSatisfy { $0.parentSKU == "SKU-A" && $0.status == .available })
    }

    func test_availableUnits_noneAvailable_empty() {
        let items = [makeSerial(id: 1, sku: "SKU-A", status: .sold)]
        let available = SerialStatusCalculator.availableUnits(from: items, sku: "SKU-A")
        XCTAssertTrue(available.isEmpty)
    }

    // MARK: - Helpers

    private func makeSerial(
        id: Int64,
        sku: String,
        status: SerialStatus
    ) -> SerializedItem {
        SerializedItem(
            id: id,
            parentSKU: sku,
            serialNumber: "SN-\(id)",
            status: status,
            receivedAt: Date()
        )
    }
}
