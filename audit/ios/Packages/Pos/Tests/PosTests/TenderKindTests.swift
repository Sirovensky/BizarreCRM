import XCTest
@testable import Pos

/// §16.5 — Tests for `TenderKind`.
final class TenderKindTests: XCTestCase {

    // MARK: - allCases coverage

    func test_allCases_has4Kinds() {
        XCTAssertEqual(TenderKind.allCases.count, 4)
    }

    func test_allCases_containsExpected() {
        let kinds = Set(TenderKind.allCases)
        XCTAssertTrue(kinds.contains(.cash))
        XCTAssertTrue(kinds.contains(.card))
        XCTAssertTrue(kinds.contains(.giftCard))
        XCTAssertTrue(kinds.contains(.storeCredit))
    }

    // MARK: - displayName

    func test_displayName_cash() {
        XCTAssertEqual(TenderKind.cash.displayName, "Cash")
    }

    func test_displayName_card() {
        XCTAssertEqual(TenderKind.card.displayName, "Card")
    }

    func test_displayName_giftCard() {
        XCTAssertEqual(TenderKind.giftCard.displayName, "Gift card")
    }

    func test_displayName_storeCredit() {
        XCTAssertEqual(TenderKind.storeCredit.displayName, "Store credit")
    }

    // MARK: - apiValue

    func test_apiValue_cash() {
        XCTAssertEqual(TenderKind.cash.apiValue, "cash")
    }

    func test_apiValue_card() {
        XCTAssertEqual(TenderKind.card.apiValue, "credit_card")
    }

    func test_apiValue_giftCard() {
        XCTAssertEqual(TenderKind.giftCard.apiValue, "gift_card")
    }

    func test_apiValue_storeCredit() {
        XCTAssertEqual(TenderKind.storeCredit.apiValue, "store_credit")
    }

    // MARK: - isAvailableWithoutHardware

    func test_cashIsAvailableWithoutHardware() {
        XCTAssertTrue(TenderKind.cash.isAvailableWithoutHardware)
    }

    func test_cardRequiresHardware() {
        XCTAssertFalse(TenderKind.card.isAvailableWithoutHardware)
    }

    func test_giftCardRequiresHardware() {
        XCTAssertFalse(TenderKind.giftCard.isAvailableWithoutHardware)
    }

    func test_storeCreditRequiresHardware() {
        XCTAssertFalse(TenderKind.storeCredit.isAvailableWithoutHardware)
    }

    // MARK: - hardwareRequiredMessage

    func test_cash_noHardwareMessage() {
        XCTAssertNil(TenderKind.cash.hardwareRequiredMessage)
    }

    func test_card_hasHardwareMessage() {
        let msg = TenderKind.card.hardwareRequiredMessage
        XCTAssertNotNil(msg)
        XCTAssertFalse(msg!.isEmpty)
    }

    func test_giftCard_hasHardwareMessage() {
        XCTAssertNotNil(TenderKind.giftCard.hardwareRequiredMessage)
    }

    func test_storeCredit_hasHardwareMessage() {
        XCTAssertNotNil(TenderKind.storeCredit.hardwareRequiredMessage)
    }

    // MARK: - systemImage

    func test_systemImages_nonEmpty() {
        for kind in TenderKind.allCases {
            XCTAssertFalse(kind.systemImage.isEmpty, "\(kind.rawValue) systemImage is empty")
        }
    }

    // MARK: - Hashable / Equatable

    func test_equatable() {
        XCTAssertEqual(TenderKind.cash, TenderKind.cash)
        XCTAssertNotEqual(TenderKind.cash, TenderKind.card)
    }

    func test_hashable_setMembership() {
        let set: Set<TenderKind> = [.cash, .cash, .card]
        XCTAssertEqual(set.count, 2)
    }
}
