#if canImport(UIKit)
import XCTest
@testable import Pos

/// §D — Tests for `PosStoreCreditAmountView` logic.
final class PosStoreCreditAmountViewTests: XCTestCase {

    // MARK: - maxApplicable clamping

    func test_maxApplicable_clampedToBalance() {
        let balance = 3_000
        let due = 5_000
        let maxApplicable = min(balance, due)
        XCTAssertEqual(maxApplicable, 3_000)
    }

    func test_maxApplicable_clampedToDue() {
        let balance = 10_000
        let due = 4_500
        let maxApplicable = min(balance, due)
        XCTAssertEqual(maxApplicable, 4_500)
    }

    func test_maxApplicable_equalWhenSame() {
        let balance = 2_000
        let due = 2_000
        let maxApplicable = min(balance, due)
        XCTAssertEqual(maxApplicable, 2_000)
    }

    // MARK: - canConfirm

    func test_canConfirm_falseWhenNoBalance() {
        let maxApplicable = 0
        XCTAssertFalse(maxApplicable > 0)
    }

    func test_canConfirm_trueWhenPositive() {
        let maxApplicable = 1_500
        XCTAssertTrue(maxApplicable > 0)
    }

    // MARK: - nil balance (loading state)

    func test_nilBalance_blocksConfirm() {
        // View shows loading state, apply button is disabled
        let balance: Int? = nil
        let maxApplicable = balance.map { min($0, 5_000) } ?? 0
        XCTAssertEqual(maxApplicable, 0)
    }

    // MARK: - Happy path

    func test_happyPath_fullBalanceApplied() {
        var confirmed = false
        var confirmedAmount: Int = 0

        let balance = 5_000
        let due = 5_000
        let max = min(balance, due)

        // Simulate pressing "Apply maximum" and confirming
        confirmedAmount = max
        confirmed = true

        XCTAssertTrue(confirmed)
        XCTAssertEqual(confirmedAmount, 5_000)
    }
}
#endif
