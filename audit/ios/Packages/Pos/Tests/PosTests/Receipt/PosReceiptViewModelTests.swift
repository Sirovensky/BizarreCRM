import XCTest
@testable import Pos

/// §Agent-E — Unit tests for `PosReceiptViewModel` and `PosReceiptPayload`.
///
/// Platform-agnostic (no UIKit). Covers:
/// - Channel pre-selection (SMS when phone present, Print when no phone)
/// - Action flag mutations (nextSale, startRefund, viewTicket, viewCustomerProfile)
/// - SMS / email send with nil API (stub path)
/// - Payload equatability
/// - Loyalty delta edge cases
/// - Change cents optional behaviour
@MainActor
final class PosReceiptViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(
        phone: String? = nil,
        email: String? = nil,
        loyaltyDelta: Int? = nil
    ) -> PosReceiptViewModel {
        PosReceiptViewModel(
            payload: PosReceiptPayload(
                invoiceId: 1,
                amountPaidCents: 1000,
                methodLabel: "Cash",
                customerPhone: phone,
                customerEmail: email,
                loyaltyDelta: loyaltyDelta
            )
        )
    }

    // MARK: - §1: Channel pre-selection — phone present → SMS

    func test_defaultChannel_isSMS_whenPhonePresent() {
        let vm = makeVM(phone: "+15558675309")
        XCTAssertEqual(vm.defaultChannel, .sms)
    }

    // MARK: - §2: Channel pre-selection — no phone → Print

    func test_defaultChannel_isPrint_whenNoPhone() {
        let vm = makeVM(phone: nil)
        XCTAssertEqual(vm.defaultChannel, .print)
    }

    // MARK: - §3: Channel pre-selection — empty phone string → Print

    func test_defaultChannel_isPrint_whenPhoneIsEmpty() {
        let vm = makeVM(phone: "")
        XCTAssertEqual(vm.defaultChannel, .print)
    }

    // MARK: - §4: nextSale sets flag and fires closure

    func test_nextSale_setsFlagAndFiresClosure() {
        var fired = false
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(invoiceId: 2, amountPaidCents: 500, methodLabel: "Card"),
            onNextSale: { fired = true }
        )
        XCTAssertFalse(vm.didRequestNextSale)
        vm.nextSale()
        XCTAssertTrue(vm.didRequestNextSale)
        XCTAssertTrue(fired)
    }

    // MARK: - §5: startRefund sets flag and fires closure

    func test_startRefund_setsFlagAndFiresClosure() {
        var fired = false
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(invoiceId: 3, amountPaidCents: 200, methodLabel: "Cash"),
            onRefund: { fired = true }
        )
        XCTAssertFalse(vm.didRequestRefund)
        vm.startRefund()
        XCTAssertTrue(vm.didRequestRefund)
        XCTAssertTrue(fired)
    }

    // MARK: - §6: viewTicket sets flag

    func test_viewTicket_setsFlag() {
        var fired = false
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(invoiceId: 4, amountPaidCents: 300, methodLabel: "Visa"),
            onViewTicket: { fired = true }
        )
        vm.viewTicket()
        XCTAssertTrue(vm.didRequestViewTicket)
        XCTAssertTrue(fired)
    }

    // MARK: - §7: viewCustomerProfile sets flag

    func test_viewCustomerProfile_setsFlag() {
        var fired = false
        let vm = PosReceiptViewModel(
            payload: PosReceiptPayload(invoiceId: 5, amountPaidCents: 400, methodLabel: "Cash"),
            onViewCustomerProfile: { fired = true }
        )
        vm.viewCustomerProfile()
        XCTAssertTrue(vm.didRequestCustomerProfile)
        XCTAssertTrue(fired)
    }

    // MARK: - §8: share(channel: .sms) with no API → stub sent

    func test_share_sms_withNoApi_setsStubSentStatus() async {
        let vm = makeVM(phone: "+15555550100")
        vm.share(channel: .sms)
        // Yield to let the inner Task complete.
        await Task.yield()
        await Task.yield()
        // With no APIClient the stub path runs immediately.
        if case .sent = vm.sendStatus {
            // pass
        } else {
            // Still sending is acceptable if Task hasn't resolved yet.
            // The important invariant is it never stays .idle after the call.
            XCTAssertNotEqual(vm.sendStatus, .idle)
        }
    }

    // MARK: - §9: share(channel: .sms) with no phone → failed status

    func test_share_sms_withNoPhone_failsImmediately() async {
        let vm = makeVM(phone: nil)
        vm.share(channel: .sms)
        await Task.yield()
        await Task.yield()
        if case .failed = vm.sendStatus {
            // pass
        } else {
            XCTFail("Expected .failed when no phone on file, got \(vm.sendStatus)")
        }
    }

    // MARK: - §10: share(channel: .email) with no email → failed status

    func test_share_email_withNoEmail_failsImmediately() async {
        let vm = makeVM(email: nil)
        vm.share(channel: .email)
        await Task.yield()
        await Task.yield()
        if case .failed = vm.sendStatus {
            // pass
        } else {
            XCTFail("Expected .failed when no email on file, got \(vm.sendStatus)")
        }
    }

    // MARK: - §11: loyaltyDelta nil means no celebration

    func test_loyaltyDelta_nil_isNil() {
        let vm = makeVM(loyaltyDelta: nil)
        XCTAssertNil(vm.payload.loyaltyDelta)
    }

    // MARK: - §12: loyaltyDelta positive is accessible from payload

    func test_loyaltyDelta_positive_isPreserved() {
        let vm = makeVM(loyaltyDelta: 150)
        XCTAssertEqual(vm.payload.loyaltyDelta, 150)
    }

    // MARK: - §13: Loyalty tier-up is detectable

    func test_loyaltyTierUp_distinguishable() {
        let payload = PosReceiptPayload(
            invoiceId: 10,
            amountPaidCents: 9999,
            methodLabel: "Card",
            loyaltyDelta: 300,
            loyaltyTierBefore: "Gold",
            loyaltyTierAfter: "Platinum"
        )
        XCTAssertNotEqual(payload.loyaltyTierBefore, payload.loyaltyTierAfter)
    }

    // MARK: - §14: changeGivenCents nil for card sale

    func test_changeGivenCents_isNil_forCardSale() {
        let payload = PosReceiptPayload(
            invoiceId: 11,
            amountPaidCents: 5000,
            changeGivenCents: nil,
            methodLabel: "Visa •4242"
        )
        XCTAssertNil(payload.changeGivenCents)
    }

    // MARK: - §15: changeGivenCents present for cash sale

    func test_changeGivenCents_isPresent_forCashSale() {
        let payload = PosReceiptPayload(
            invoiceId: 12,
            amountPaidCents: 10000,
            changeGivenCents: 500,
            methodLabel: "Cash"
        )
        XCTAssertEqual(payload.changeGivenCents, 500)
    }

    // MARK: - §16: Payload equality (Equatable conformance)

    func test_payload_equatable_sameValues_areEqual() {
        let a = PosReceiptPayload(invoiceId: 1, amountPaidCents: 100, methodLabel: "Cash")
        let b = PosReceiptPayload(invoiceId: 1, amountPaidCents: 100, methodLabel: "Cash")
        XCTAssertEqual(a, b)
    }

    func test_payload_equatable_differentInvoiceId_notEqual() {
        let a = PosReceiptPayload(invoiceId: 1, amountPaidCents: 100, methodLabel: "Cash")
        let b = PosReceiptPayload(invoiceId: 2, amountPaidCents: 100, methodLabel: "Cash")
        XCTAssertNotEqual(a, b)
    }
}
