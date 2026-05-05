import XCTest
@testable import Invoices
import Networking

// §7.7 buildPaymentHistory + InvoiceDetailEndpoints helpers

final class InvoicePaymentHistoryTests: XCTestCase {

    // MARK: - buildPaymentHistory

    func test_buildPaymentHistory_emptyPayments_returnsEmpty() {
        let inv = invoice(status: "unpaid", amountPaid: 0, amountDue: 100, paymentsJSON: "[]")
        let entries = buildPaymentHistory(from: inv)
        XCTAssertTrue(entries.isEmpty)
    }

    func test_buildPaymentHistory_withPayments_returnsEntries() {
        let paymentsJSON = "[{\"id\":1,\"amount\":25.0,\"method\":\"cash\",\"payment_type\":\"payment\",\"created_at\":\"2025-01-01\"},{\"id\":2,\"amount\":25.0,\"method\":\"card\",\"payment_type\":\"payment\",\"created_at\":\"2025-01-02\"}]"
        let inv = invoice(status: "partial", amountPaid: 50, paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries.count, 2)
    }

    func test_buildPaymentHistory_paymentKind_isPayment() {
        let paymentsJSON = "[{\"id\":1,\"amount\":10.0,\"payment_type\":\"payment\",\"created_at\":\"2025-01-01\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries.first?.kind, .payment)
    }

    func test_buildPaymentHistory_refundType_isRefund() {
        let paymentsJSON = "[{\"id\":1,\"amount\":10.0,\"payment_type\":\"refund\",\"created_at\":\"2025-01-01\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries.first?.kind, .refund)
    }

    func test_buildPaymentHistory_voidStatus_addsVoidEntry() {
        let inv = invoice(status: "void", amountPaid: 0, amountDue: 0, paymentsJSON: "[]")
        let entries = buildPaymentHistory(from: inv)
        XCTAssertTrue(entries.contains { $0.kind == .void })
    }

    func test_buildPaymentHistory_nonVoidStatus_noVoidEntry() {
        let inv = invoice(status: "paid", paymentsJSON: "[]")
        let entries = buildPaymentHistory(from: inv)
        XCTAssertFalse(entries.contains { $0.kind == .void })
    }

    func test_buildPaymentHistory_sortedDescendingByTimestamp() {
        let paymentsJSON = "[{\"id\":1,\"amount\":10.0,\"payment_type\":\"payment\",\"created_at\":\"2025-01-01\"},{\"id\":2,\"amount\":20.0,\"payment_type\":\"payment\",\"created_at\":\"2025-03-01\"},{\"id\":3,\"amount\":15.0,\"payment_type\":\"payment\",\"created_at\":\"2025-02-01\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries[0].timestamp, "2025-03-01")
        XCTAssertEqual(entries[1].timestamp, "2025-02-01")
        XCTAssertEqual(entries[2].timestamp, "2025-01-01")
    }

    func test_buildPaymentHistory_amountConvertedToCents() {
        let paymentsJSON = "[{\"id\":1,\"amount\":12.50,\"payment_type\":\"payment\",\"created_at\":\"2025-01-01\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries.first?.amountCents, 1250)
    }

    func test_buildPaymentHistory_refundAmountIsNegative() {
        let paymentsJSON = "[{\"id\":1,\"amount\":10.0,\"payment_type\":\"refund\",\"created_at\":\"2025-01-01\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertEqual(entries.first?.amountCents, -1000)
    }

    // MARK: - InvoiceDetail.canPay

    func test_canPay_trueWhenUnpaidAndBalanceDue() {
        let inv = invoice(status: "unpaid", amountPaid: 0, amountDue: 100)
        XCTAssertTrue(inv.canPay)
    }

    func test_canPay_falseWhenPaid() {
        let inv = invoice(status: "paid", amountPaid: 100, amountDue: 0)
        XCTAssertFalse(inv.canPay)
    }

    func test_canPay_falseWhenVoid() {
        let inv = invoice(status: "void", amountPaid: 0, amountDue: 100)
        XCTAssertFalse(inv.canPay)
    }

    func test_canPay_falseWhenNoDue() {
        let inv = invoice(status: "partial", amountPaid: 100, amountDue: 0)
        XCTAssertFalse(inv.canPay)
    }

    // MARK: - InvoiceDetail.canRefund

    func test_canRefund_trueWhenHasPayments() {
        let inv = invoice(status: "paid", amountPaid: 100, amountDue: 0)
        XCTAssertTrue(inv.canRefund)
    }

    func test_canRefund_falseWhenNoPayments() {
        let inv = invoice(status: "unpaid", amountPaid: 0, amountDue: 100)
        XCTAssertFalse(inv.canRefund)
    }

    func test_canRefund_falseWhenVoid() {
        let inv = invoice(status: "void", amountPaid: 50, amountDue: 0)
        XCTAssertFalse(inv.canRefund)
    }

    // MARK: - InvoiceDetail.canVoid

    func test_canVoid_trueWhenDraftNoPayments() {
        let inv = invoice(status: "draft", amountPaid: 0, amountDue: 100)
        XCTAssertTrue(inv.canVoid)
    }

    func test_canVoid_trueWhenUnpaidNoPayments() {
        let inv = invoice(status: "unpaid", amountPaid: 0, amountDue: 100)
        XCTAssertTrue(inv.canVoid)
    }

    func test_canVoid_falseWhenAlreadyVoid() {
        let inv = invoice(status: "void", amountPaid: 0, amountDue: 0)
        XCTAssertFalse(inv.canVoid)
    }

    func test_canVoid_falseWhenPaid() {
        let inv = invoice(status: "paid", amountPaid: 100, amountDue: 0)
        XCTAssertFalse(inv.canVoid)
    }

    func test_canVoid_falseWhenHasPayments() {
        let inv = invoice(status: "partial", amountPaid: 50, amountDue: 50)
        XCTAssertFalse(inv.canVoid)
    }
}

// MARK: - Fixture builder

private func invoice(
    status: String = "unpaid",
    amountPaid: Double = 0,
    amountDue: Double = 100,
    paymentsJSON: String = "null"
) -> InvoiceDetail {
    let jsonStr = "{\"id\":1,\"status\":\"\(status)\",\"amount_paid\":\(amountPaid),\"amount_due\":\(amountDue),\"payments\":\(paymentsJSON)}"
    let json = jsonStr.data(using: .utf8)!
    let decoder = JSONDecoder()
    return try! decoder.decode(InvoiceDetail.self, from: json)
}
