import XCTest
@testable import Pos

/// §16.6 — Tests for `TenderMethod` additions (check tender, split tender).
final class TenderMethodTests: XCTestCase {

    func test_check_isReady() {
        XCTAssertTrue(TenderMethod.check.isReady)
    }

    func test_check_apiValue() {
        XCTAssertEqual(TenderMethod.check.apiValue, "check")
    }

    func test_check_requiresDetailsSheet() {
        XCTAssertTrue(TenderMethod.check.requiresDetailsSheet)
        XCTAssertFalse(TenderMethod.cash.requiresDetailsSheet)
        XCTAssertFalse(TenderMethod.giftCard.requiresDetailsSheet)
    }

    func test_allCases_haveNonEmptyDisplayName() {
        for method in TenderMethod.allCases {
            XCTAssertFalse(method.displayName.isEmpty, "\(method) has empty displayName")
        }
    }

    func test_allCases_haveNonEmptySystemImage() {
        for method in TenderMethod.allCases {
            XCTAssertFalse(method.systemImage.isEmpty, "\(method) has empty systemImage")
        }
    }
}

/// §16.3 — Tests for Cart ticket link.
final class CartTicketLinkTests: XCTestCase {

    @MainActor
    func test_linkToTicket_setsLinkedId() {
        let cart = Cart()
        cart.linkToTicket(id: 1234)
        XCTAssertEqual(cart.linkedTicketId, 1234)
    }

    @MainActor
    func test_unlinkTicket_clearsId() {
        let cart = Cart()
        cart.linkToTicket(id: 99)
        cart.unlinkTicket()
        XCTAssertNil(cart.linkedTicketId)
    }

    @MainActor
    func test_initial_linkedId_isNil() {
        let cart = Cart()
        XCTAssertNil(cart.linkedTicketId)
    }
}
