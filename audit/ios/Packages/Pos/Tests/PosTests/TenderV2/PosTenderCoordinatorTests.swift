#if canImport(UIKit)
import XCTest
import Networking
@testable import Pos

/// §D — Tests for `PosTenderCoordinator`.
/// ≥8 cases required by spec; this suite has 12.
@MainActor
final class PosTenderCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeCoordinator(
        totalCents: Int = 10_000,
        api: TenderV2MockAPIClient = TenderV2MockAPIClient()
    ) -> PosTenderCoordinator {
        PosTenderCoordinator(
            totalCents: totalCents,
            baseRequest: PosTransactionRequest(
                items: [],
                idempotencyKey: "test-key-\(UUID())"
            ),
            api: api
        )
    }

    private func makeSuccessAPI(invoiceId: Int64 = 99, totalCents: Int = 10_000) -> TenderV2MockAPIClient {
        let api = TenderV2MockAPIClient()
        api.transactionResult = .success(PosTransactionResponse(
            invoice: PosTransactionInvoice(id: invoiceId, orderId: "ORD-1", totalCents: totalCents)
        ))
        return api
    }

    // MARK: - Case 1: Initial state

    func test_initialState() {
        let c = makeCoordinator(totalCents: 5_000)
        XCTAssertNil(c.method)
        XCTAssertEqual(c.remaining, 5_000)
        XCTAssertTrue(c.appliedTenders.isEmpty)
        XCTAssertFalse(c.isSplit)
        XCTAssertEqual(c.stage, .method)
        XCTAssertEqual(c.tipCents, 0)
    }

    // MARK: - Case 2: Full single-method payment → .confirmed

    func test_fullPayment_singleMethod_transitionsToConfirmed() async {
        let api = makeSuccessAPI(totalCents: 10_000)
        let c = makeCoordinator(totalCents: 10_000, api: api)

        c.selectMethod(.cash)
        XCTAssertEqual(c.stage, .amount)

        c.applyTender(amountCents: 10_000)
        // remaining == 0 but stage doesn't auto-advance to .confirmed until confirm() is called
        XCTAssertEqual(c.remaining, 0)

        await c.confirm()

        XCTAssertEqual(c.stage, .confirmed)
        XCTAssertNotNil(c.confirmResult)
        XCTAssertEqual(c.confirmResult?.invoiceId, 99)
        XCTAssertEqual(c.confirmResult?.changeCents, 0)
    }

    // MARK: - Case 3: Partial payment → rolls back to method picker

    func test_partialPayment_rollsBackToMethodPicker() {
        let c = makeCoordinator(totalCents: 10_000)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 4_000)  // partial

        XCTAssertEqual(c.remaining, 6_000)
        XCTAssertEqual(c.stage, .method)
        XCTAssertNil(c.method)
        XCTAssertEqual(c.appliedTenders.count, 1)
    }

    // MARK: - Case 4: Partial payment → isSplit becomes true

    func test_isSplit_trueAfterPartialPayment() {
        let c = makeCoordinator(totalCents: 10_000)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 3_000)

        XCTAssertTrue(c.isSplit)
        XCTAssertEqual(c.remaining, 7_000)
    }

    // MARK: - Case 5: Split tender sum covers full total → can confirm

    func test_splitTenderSum_coversTotal() async {
        let api = makeSuccessAPI(totalCents: 10_000)
        let c = makeCoordinator(totalCents: 10_000, api: api)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 5_000)

        c.selectMethod(.giftCard)
        c.applyTender(amountCents: 5_000, reference: "••••4C7A")

        XCTAssertEqual(c.remaining, 0)

        await c.confirm()
        XCTAssertEqual(c.stage, .confirmed)
        XCTAssertEqual(api.transactionCallCount, 1)
    }

    // MARK: - Case 6: Cancel amount entry returns to method picker

    func test_cancelAmountEntry_returnsToMethodPicker() {
        let c = makeCoordinator(totalCents: 10_000)

        c.selectMethod(.card)
        XCTAssertEqual(c.stage, .amount)

        c.cancelAmountEntry()
        XCTAssertEqual(c.stage, .method)
        XCTAssertNil(c.method)
    }

    // MARK: - Case 7: Cash received must be >= due

    func test_applyTender_clampedToRemaining() {
        let c = makeCoordinator(totalCents: 5_000)

        c.selectMethod(.cash)
        // Attempt to apply more than due — coordinator clamps to remaining
        c.applyTender(amountCents: 9_000)

        XCTAssertEqual(c.remaining, 0)
        XCTAssertEqual(c.appliedTenders.first?.amountCents, 5_000)
    }

    // MARK: - Case 8: Method switch mid-flow

    func test_methodSwitch_midFlow() {
        let c = makeCoordinator(totalCents: 10_000)

        c.selectMethod(.cash)
        XCTAssertEqual(c.method, .cash)

        c.cancelAmountEntry()
        c.selectMethod(.giftCard)
        XCTAssertEqual(c.method, .giftCard)
        XCTAssertEqual(c.stage, .amount)
    }

    // MARK: - Case 9: Add tip

    func test_setTip_storesTipCents() {
        let c = makeCoordinator(totalCents: 10_000)
        c.setTip(cents: 150)
        XCTAssertEqual(c.tipCents, 150)
    }

    func test_setTip_clampsToZero_whenNegative() {
        let c = makeCoordinator(totalCents: 10_000)
        c.setTip(cents: -200)
        XCTAssertEqual(c.tipCents, 0)
    }

    // MARK: - Case 10: Confirm only fires .confirmed once

    func test_confirm_triggersConfirmedOnce() async {
        let api = makeSuccessAPI(totalCents: 5_000)
        let c = makeCoordinator(totalCents: 5_000, api: api)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 5_000)

        await c.confirm()
        await c.confirm()  // second call should be a no-op

        XCTAssertEqual(api.transactionCallCount, 1, "confirm() must not double-post")
        XCTAssertEqual(c.stage, .confirmed)
    }

    // MARK: - Case 11: Network error surfaces errorMessage

    func test_confirm_networkError_surfacesErrorMessage() async {
        let api = TenderV2MockAPIClient()
        api.transactionResult = .failure(TenderV2MockError.network)
        let c = makeCoordinator(totalCents: 5_000, api: api)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 5_000)

        await c.confirm()

        XCTAssertNotNil(c.errorMessage)
        XCTAssertNotEqual(c.stage, .confirmed)
        XCTAssertFalse(c.isConfirming)
    }

    // MARK: - Case 12a: confirm() is no-op when remaining > 0

    func test_confirm_noOp_whenRemainingGreaterThanZero() async {
        let api = makeSuccessAPI(totalCents: 10_000)
        let c = makeCoordinator(totalCents: 10_000, api: api)

        // Apply only partial payment
        c.selectMethod(.cash)
        c.applyTender(amountCents: 5_000)
        XCTAssertEqual(c.remaining, 5_000)

        await c.confirm()  // should be a no-op

        XCTAssertNotEqual(c.stage, .confirmed)
        XCTAssertEqual(api.transactionCallCount, 0)
    }

    // MARK: - Case 12: Reset restores initial state

    func test_reset_restoresInitialState() async {
        let api = makeSuccessAPI(totalCents: 10_000)
        let c = makeCoordinator(totalCents: 10_000, api: api)

        c.selectMethod(.cash)
        c.applyTender(amountCents: 10_000)
        await c.confirm()

        c.reset()

        XCTAssertEqual(c.stage, .method)
        XCTAssertNil(c.method)
        XCTAssertTrue(c.appliedTenders.isEmpty)
        XCTAssertEqual(c.remaining, 10_000)
        XCTAssertEqual(c.tipCents, 0)
        XCTAssertNil(c.errorMessage)
        XCTAssertNil(c.confirmResult)
    }
}
#endif
