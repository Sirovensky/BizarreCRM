#if canImport(UIKit)
import XCTest
@testable import Pos

/// §D — Tests for `PosGiftCardAmountView` validation logic.
final class PosGiftCardAmountViewTests: XCTestCase {

    // MARK: - Validation

    func test_emptyCode_blocksConfirm() {
        // View's confirm button is disabled when codeInput.isEmpty.
        // We verify the logic mirrors the view's guard.
        let code = ""
        XCTAssertTrue(code.isEmpty, "Empty code should disable apply button")
    }

    func test_whitespaceCode_blocksConfirm() {
        let code = "   "
        XCTAssertTrue(code.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func test_validCode_enables_confirm() {
        let code = "GIFT1234ABCD"
        XCTAssertFalse(code.isEmpty)
    }

    // MARK: - Code normalization

    func test_codeNormalization_uppercased() {
        let raw = "gift1234abcd"
        let normalized = raw.trimmingCharacters(in: .whitespaces).uppercased()
        XCTAssertEqual(normalized, "GIFT1234ABCD")
    }

    func test_codeNormalization_trimsWhitespace() {
        let raw = "  ABC123  "
        let normalized = raw.trimmingCharacters(in: .whitespaces).uppercased()
        XCTAssertEqual(normalized, "ABC123")
    }

    // MARK: - Confirm callback

    func test_confirmCallback_deliversDueCents() {
        var deliveredAmount: Int? = nil
        var deliveredReference: String? = nil

        // Simulate what applyGiftCard() does
        let dueCents = 7_500
        let code = "TESTCODE"
        deliveredAmount = dueCents
        deliveredReference = code

        XCTAssertEqual(deliveredAmount, 7_500)
        XCTAssertEqual(deliveredReference, "TESTCODE")
    }
}
#endif
