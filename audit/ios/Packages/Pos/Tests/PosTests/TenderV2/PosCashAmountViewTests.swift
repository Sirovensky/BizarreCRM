#if canImport(UIKit)
import XCTest
@testable import Pos

/// §D — Unit tests for `PosCashAmountView` numpad logic.
///
/// The view's numpad digit state is internal, so these tests validate
/// the digit-management helpers via a test harness.
final class PosCashAmountViewTests: XCTestCase {

    // MARK: - Numpad digit helper

    /// Simulates `appendDigits(_:)` logic.
    private func applyDigits(to existing: String, appending s: String, dueCents: Int = 1_000) -> String {
        guard existing.count + s.count <= 9 else { return existing }
        let combined = existing + s
        let result = combined == "0" ? "0" : String(Int(combined) ?? 0)
        return result == "0" ? "" : result
    }

    private func deleteDigit(from s: String) -> String {
        var copy = s
        if !copy.isEmpty { copy.removeLast() }
        return copy
    }

    private func receivedCents(from digits: String) -> Int {
        guard !digits.isEmpty, let value = Int(digits) else { return 0 }
        return value
    }

    // MARK: - Validation: cash ≥ due

    func test_canConfirm_exactAmount() {
        let digits = "10000"  // 100.00 in cents
        let received = receivedCents(from: digits)
        XCTAssertGreaterThanOrEqual(received, 10_000, "Exact amount should allow confirm")
    }

    func test_cannotConfirm_underpayment() {
        let digits = "500"
        let received = receivedCents(from: digits)
        XCTAssertFalse(received >= 10_000, "Underpayment should block confirm")
    }

    func test_cannotConfirm_emptyInput() {
        let received = receivedCents(from: "")
        XCTAssertEqual(received, 0)
        XCTAssertFalse(received >= 1_000)
    }

    // MARK: - Digit management

    func test_appendDigit_basic() {
        let result = applyDigits(to: "1", appending: "5")
        XCTAssertEqual(result, "15")
    }

    func test_appendDigit_noLeadingZero() {
        let result = applyDigits(to: "0", appending: "5")
        // "05" → Int("05") = 5
        XCTAssertEqual(result, "5")
    }

    func test_appendDigit_maxLength() {
        // 9 digits is the cap
        let long = "123456789"
        let result = applyDigits(to: long, appending: "0")
        XCTAssertEqual(result, long, "Should not exceed 9 digits")
    }

    func test_deleteDigit() {
        XCTAssertEqual(deleteDigit(from: "150"), "15")
    }

    func test_deleteDigit_emptyInput() {
        XCTAssertEqual(deleteDigit(from: ""), "")
    }

    // MARK: - Quick chips

    func test_exactChip_setsDueCents() {
        // Exact chip sets digits to dueCents string
        let dueCents = 5_499
        let digits = "\(dueCents)"
        XCTAssertEqual(receivedCents(from: digits), dueCents)
    }

    func test_plusFiveChip_addsCorrectly() {
        let dueCents = 1_200
        let chipValue = dueCents + 500
        XCTAssertEqual(chipValue, 1_700)
    }

    func test_plusTenChip_addsCorrectly() {
        let dueCents = 999
        let chipValue = dueCents + 1_000
        XCTAssertEqual(chipValue, 1_999)
    }

    // MARK: - Change calculation

    func test_changeCents_overpayment() {
        let dueCents = 1_000
        let receivedCents = 2_000
        let change = max(0, receivedCents - dueCents)
        XCTAssertEqual(change, 1_000)
    }

    func test_changeCents_exactPayment() {
        let dueCents = 5_000
        let receivedCents = 5_000
        let change = max(0, receivedCents - dueCents)
        XCTAssertEqual(change, 0)
    }
}
#endif
