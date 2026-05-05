#if canImport(UIKit)
import XCTest
import Networking
@testable import Pos

/// §D — Tests for `AppliedTenderV2`.
final class AppliedTenderV2Tests: XCTestCase {

    // MARK: - Validation

    func test_init_clampNegativeAmountToZero() {
        let tender = AppliedTenderV2(method: .cash, amountCents: -500)
        XCTAssertEqual(tender.amountCents, 0)
    }

    func test_init_storesPositiveAmount() {
        let tender = AppliedTenderV2(method: .giftCard, amountCents: 2_500, reference: "••••ABCD")
        XCTAssertEqual(tender.amountCents, 2_500)
        XCTAssertEqual(tender.reference, "••••ABCD")
    }

    // MARK: - toPaymentLeg

    func test_toPaymentLeg_correctMethod() {
        let tender = AppliedTenderV2(method: .cash, amountCents: 1_000)
        let leg = tender.toPaymentLeg()
        XCTAssertEqual(leg.method, "cash")
    }

    func test_toPaymentLeg_convertsAmountToDollars() {
        let tender = AppliedTenderV2(method: .cash, amountCents: 1_050)
        let leg = tender.toPaymentLeg()
        XCTAssertEqual(leg.amount, 10.50, accuracy: 0.001)
    }

    func test_toPaymentLeg_forwardsReference() {
        let tender = AppliedTenderV2(method: .giftCard, amountCents: 500, reference: "ABCD")
        let leg = tender.toPaymentLeg()
        XCTAssertEqual(leg.reference, "ABCD")
    }

    // MARK: - Identity

    func test_uniqueIDs() {
        let t1 = AppliedTenderV2(method: .cash, amountCents: 100)
        let t2 = AppliedTenderV2(method: .cash, amountCents: 100)
        XCTAssertNotEqual(t1.id, t2.id)
    }

    func test_equatableByValue() {
        let id = UUID()
        let t1 = AppliedTenderV2(id: id, method: .cash, amountCents: 100)
        let t2 = AppliedTenderV2(id: id, method: .cash, amountCents: 100)
        XCTAssertEqual(t1, t2)
    }
}
#endif
