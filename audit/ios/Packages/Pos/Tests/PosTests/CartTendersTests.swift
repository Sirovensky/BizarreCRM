import XCTest
@testable import Pos

@MainActor
final class CartTendersTests: XCTestCase {

    // MARK: - Fixtures

    private func cart(with total: Int) -> Cart {
        // Build a cart with a single line whose line total equals the
        // target. `unitPrice` is in dollars, so we go via `Decimal` to
        // keep parity with the rest of the money pipeline.
        let cart = Cart()
        let price = Decimal(total) / 100
        cart.add(CartItem(name: "Widget", unitPrice: price))
        return cart
    }

    private func gc(_ amount: Int, id: String = "abc123") -> AppliedTender {
        AppliedTender(
            kind: .giftCard,
            amountCents: amount,
            label: AppliedTender.giftCardLabel(code: id),
            reference: "42"
        )
    }

    private func credit(_ amount: Int) -> AppliedTender {
        AppliedTender(
            kind: .storeCredit,
            amountCents: amount,
            label: "Store credit",
            reference: "1"
        )
    }

    // MARK: - apply / remaining

    func test_newCart_remainingEqualsTotal_noTenders() {
        let c = cart(with: 5_000)
        XCTAssertEqual(c.remainingCents, c.totalCents)
        XCTAssertEqual(c.appliedTendersCents, 0)
        XCTAssertFalse(c.isFullyTendered)
    }

    func test_apply_reducesRemaining_byAmount() {
        let c = cart(with: 5_000)
        c.apply(tender: gc(2_000))
        XCTAssertEqual(c.appliedTendersCents, 2_000)
        XCTAssertEqual(c.remainingCents, 3_000)
        XCTAssertFalse(c.isFullyTendered)
    }

    func test_apply_multipleTenders_sumCorrectly() {
        let c = cart(with: 10_000)
        c.apply(tender: gc(3_000))
        c.apply(tender: credit(2_500))
        XCTAssertEqual(c.appliedTendersCents, 5_500)
        XCTAssertEqual(c.remainingCents, 4_500)
        XCTAssertEqual(c.appliedTenders.count, 2)
    }

    // Over-tender clamps remaining at zero — server enforces strict
    // equality; locally we render a sane floor.
    func test_overTender_remainingClampsToZero() {
        let c = cart(with: 2_000)
        c.apply(tender: gc(5_000))
        XCTAssertEqual(c.remainingCents, 0)
        XCTAssertTrue(c.isFullyTendered)
    }

    func test_exactTender_fullyCoversCart() {
        let c = cart(with: 4_200)
        c.apply(tender: gc(4_200))
        XCTAssertEqual(c.remainingCents, 0)
        XCTAssertTrue(c.isFullyTendered)
    }

    // MARK: - removeTender

    func test_removeTender_restoresRemaining() {
        let c = cart(with: 5_000)
        let t = gc(2_000)
        c.apply(tender: t)
        c.removeTender(id: t.id)
        XCTAssertEqual(c.appliedTendersCents, 0)
        XCTAssertEqual(c.remainingCents, 5_000)
        XCTAssertFalse(c.isFullyTendered)
    }

    func test_removeTender_unknownId_isNoOp() {
        let c = cart(with: 3_000)
        c.apply(tender: gc(1_000))
        c.removeTender(id: UUID())
        XCTAssertEqual(c.appliedTenders.count, 1)
        XCTAssertEqual(c.remainingCents, 2_000)
    }

    // MARK: - clearTenders / clear

    func test_clearTenders_dropsAllButKeepsItems() {
        let c = cart(with: 5_000)
        c.apply(tender: gc(1_000))
        c.apply(tender: credit(1_500))
        c.clearTenders()
        XCTAssertTrue(c.appliedTenders.isEmpty)
        XCTAssertEqual(c.remainingCents, 5_000)
        XCTAssertFalse(c.isEmpty)
    }

    func test_clear_wipesTendersToo() {
        let c = cart(with: 5_000)
        c.apply(tender: gc(2_500))
        c.clear()
        XCTAssertTrue(c.appliedTenders.isEmpty)
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.remainingCents, 0)
    }

    // MARK: - zero-amount guards

    func test_apply_zeroAmount_isDropped() {
        let c = cart(with: 1_000)
        c.apply(tender: AppliedTender(kind: .giftCard, amountCents: 0, label: "x"))
        XCTAssertTrue(c.appliedTenders.isEmpty)
        XCTAssertEqual(c.remainingCents, 1_000)
    }

    func test_apply_negativeAmount_clampsToZero_thenDropped() {
        let c = cart(with: 1_000)
        c.apply(tender: AppliedTender(kind: .giftCard, amountCents: -500, label: "x"))
        XCTAssertTrue(c.appliedTenders.isEmpty)
    }

    // MARK: - isFullyTendered rules

    func test_isFullyTendered_falseOnEmptyCart_evenWithTenders() {
        let c = Cart()
        // Manually push a tender (via `apply`) to simulate a weird edge —
        // the cart has no items, so Complete should stay hidden.
        c.apply(tender: gc(100))
        XCTAssertFalse(c.isFullyTendered)
    }

    // MARK: - label masking

    func test_giftCardLabel_showsLastFour_uppercased() {
        let label = AppliedTender.giftCardLabel(code: "abcdef1234567890")
        XCTAssertEqual(label, "Gift card ••••7890")
    }

    func test_giftCardLabel_shortCode_stillRenders() {
        let label = AppliedTender.giftCardLabel(code: "ab")
        XCTAssertEqual(label, "Gift card ••••AB")
    }

    func test_giftCardLabel_emptyCode_fallsBackToGeneric() {
        let label = AppliedTender.giftCardLabel(code: "")
        XCTAssertEqual(label, "Gift card")
    }
}
