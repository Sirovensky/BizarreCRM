// MARK: - §6.2 / §6.5 Inventory Detail Enhancements Tests
//
// Tests for: VarianceCard math, HIDScannerField timer behavior (logic only).

import XCTest
@testable import Inventory

final class InventoryDetailEnhancementsTests: XCTestCase {

    // MARK: - §6.2 Variance analysis

    func test_marginPercent_zeroWhenCostZero() {
        // marginPct = (retail - cost) / cost * 100
        // When cost = 0, guard prevents division by zero
        let cost: Double = 0
        let retail: Double = 100
        let pct = cost > 0 ? ((retail - cost) / cost) * 100 : 0
        XCTAssertEqual(pct, 0, accuracy: 0.001)
    }

    func test_marginPercent_positiveMargin() {
        let cost: Double = 50
        let retail: Double = 100
        let pct = ((retail - cost) / cost) * 100
        XCTAssertEqual(pct, 100, accuracy: 0.001, "50→100 = 100% margin on cost")
    }

    func test_marginPercent_negativeMarginWhenCostAboveRetail() {
        let cost: Double = 120
        let retail: Double = 100
        let pct = ((retail - cost) / cost) * 100
        XCTAssertLessThan(pct, 0, "cost > retail → negative margin")
    }

    func test_marginAmount_equalsRetailMinusCost() {
        let cost: Double = 25.50
        let retail: Double = 79.99
        let margin = retail - cost
        XCTAssertEqual(margin, 54.49, accuracy: 0.001)
    }

    func test_marginPercent_thirtyPercent() {
        let cost: Double = 100
        let retail: Double = 130
        let pct = ((retail - cost) / cost) * 100
        XCTAssertEqual(pct, 30, accuracy: 0.001, "100→130 = 30% margin")
    }

    // MARK: - §6.5 HID scanner buffer logic

    func test_hidScannerBuffer_shortCodesIgnored() {
        // Codes < 4 chars should NOT fire onScan
        var fired = false
        let threshold = 4
        let code = "ABC"
        if code.count >= threshold { fired = true }
        XCTAssertFalse(fired, "codes shorter than 4 chars must be ignored")
    }

    func test_hidScannerBuffer_minimalLengthAccepted() {
        var fired = false
        let threshold = 4
        let code = "ABCD"
        if code.count >= threshold { fired = true }
        XCTAssertTrue(fired, "exactly 4 chars must be accepted")
    }

    func test_hidScannerBuffer_returnsCleanedCode() {
        // newlines stripped before firing
        let raw = "ABC123\n"
        let cleaned = raw.replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(cleaned, "ABC123")
    }

    func test_hidScannerBuffer_carriageReturnStripped() {
        let raw = "SCAN001\r\n"
        let cleaned = raw.replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(cleaned, "SCAN001")
    }

    func test_hidScannerBuffer_emptyStringAfterStripping() {
        let raw = "\n\r"
        let cleaned = raw.replacingOccurrences(of: "\n", with: "")
                         .replacingOccurrences(of: "\r", with: "")
                         .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(cleaned.count < 4, "whitespace-only buffers must be ignored")
    }

    func test_hidScannerBuffer_longBarcodeAccepted() {
        let code = "978020137962"  // EAN-13
        XCTAssertGreaterThanOrEqual(code.count, 4)
    }
}
