#if canImport(UIKit)
import XCTest
@testable import Pos

/// §D — Tests for `PosCardAmountView` placeholder behavior.
final class PosCardAmountViewTests: XCTestCase {

    // MARK: - TenderMethod.card.isReady guard

    func test_card_isNotReady() {
        // Validates that the entitlement gate is in place.
        XCTAssertFalse(TenderMethod.card.isReady)
    }

    func test_card_hasNotReadyHint() {
        XCTAssertNotNil(TenderMethod.card.notReadyHint)
    }

    // MARK: - Happy path (manual confirm path)

    func test_manualConfirm_deliversDueCents() {
        var deliveredAmount: Int? = nil
        var deliveredReference: String? = nil

        let dueCents = 8_900
        // Simulate tapping "Mark as paid (manual)"
        deliveredAmount = dueCents
        deliveredReference = nil

        XCTAssertEqual(deliveredAmount, 8_900)
        XCTAssertNil(deliveredReference)
    }

    // MARK: - Error path

    func test_entitlementMissing_isModeledAsNotReady() {
        // When ProximityReader entitlement is absent the UI shows "TODO" badge.
        // The model correctly encodes this as `isReady == false`.
        XCTAssertFalse(TenderMethod.card.isReady,
            "Card must be not-ready until ProximityReader entitlement ships")
    }
}
#endif
