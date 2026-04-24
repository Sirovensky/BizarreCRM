#if canImport(UIKit)
import XCTest
@testable import Pos

/// §D — Tests for `TenderMethod`.
final class TenderMethodTests: XCTestCase {

    // MARK: - API values

    func test_apiValue_cash() {
        XCTAssertEqual(TenderMethod.cash.apiValue, "cash")
    }

    func test_apiValue_card() {
        XCTAssertEqual(TenderMethod.card.apiValue, "credit_card")
    }

    func test_apiValue_giftCard() {
        XCTAssertEqual(TenderMethod.giftCard.apiValue, "gift_card")
    }

    func test_apiValue_storeCredit() {
        XCTAssertEqual(TenderMethod.storeCredit.apiValue, "store_credit")
    }

    // MARK: - Availability

    func test_cashIsReady() {
        XCTAssertTrue(TenderMethod.cash.isReady)
    }

    func test_cardIsNotReady() {
        // ProximityReader entitlement pending
        XCTAssertFalse(TenderMethod.card.isReady)
    }

    func test_giftCardIsReady() {
        XCTAssertTrue(TenderMethod.giftCard.isReady)
    }

    func test_storeCreditIsReady() {
        XCTAssertTrue(TenderMethod.storeCredit.isReady)
    }

    // MARK: - Display names

    func test_displayNames_nonEmpty() {
        for method in TenderMethod.allCases {
            XCTAssertFalse(method.displayName.isEmpty, "\(method) has empty displayName")
        }
    }

    // MARK: - All cases coverage

    func test_allCasesCount() {
        XCTAssertEqual(TenderMethod.allCases.count, 4)
    }

    func test_notReadyHint_onlyForCard() {
        XCTAssertNotNil(TenderMethod.card.notReadyHint)
        XCTAssertNil(TenderMethod.cash.notReadyHint)
        XCTAssertNil(TenderMethod.giftCard.notReadyHint)
        XCTAssertNil(TenderMethod.storeCredit.notReadyHint)
    }
}
#endif
