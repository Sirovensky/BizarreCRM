import XCTest
@testable import Invoices
import Networking

// §7.2 buildInvoiceTimeline tests

final class InvoiceTimelineTests: XCTestCase {

    // MARK: - Helpers

    private func invoice(status: String = "unpaid",
                         createdAt: String = "2025-01-01T10:00:00Z",
                         updatedAt: String? = nil,
                         notes: String? = nil,
                         paymentsJSON: String = "null",
                         createdByName: String? = nil) -> InvoiceDetail {
        var updatedStr = ""
        if let u = updatedAt {
            updatedStr = ",\"updated_at\":\"\(u)\""
        }
        var notesStr = ""
        if let n = notes {
            let escaped = n.replacingOccurrences(of: "\"", with: "\\\"")
            notesStr = ",\"notes\":\"\(escaped)\""
        }
        var byStr = ""
        if let b = createdByName {
            byStr = ",\"created_by_name\":\"\(b)\""
        }
        let json = "{\"id\":1,\"status\":\"\(status)\",\"created_at\":\"\(createdAt)\"\(updatedStr)\(notesStr)\(byStr),\"amount_paid\":0,\"amount_due\":100,\"payments\":\(paymentsJSON)}"
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(InvoiceDetail.self, from: data)
    }

    // MARK: - Created event

    func test_timeline_includesCreatedEvent() {
        let inv = invoice()
        let events = buildInvoiceTimeline(from: inv)
        let hasCreated = events.contains { if case .created = $0 { return true }; return false }
        XCTAssertTrue(hasCreated)
    }

    func test_timeline_createdEvent_hasOperatorName() {
        let inv = invoice(createdByName: "Alice Smith")
        let events = buildInvoiceTimeline(from: inv)
        let created = events.first { if case .created = $0 { return true }; return false }
        guard case let .created(_, by) = created else {
            XCTFail("No created event")
            return
        }
        XCTAssertEqual(by, "Alice Smith")
    }

    // MARK: - Payment events

    func test_timeline_withPayment_includesPaymentEvent() {
        let paymentsJSON = "[{\"id\":1,\"amount\":50.0,\"method\":\"cash\",\"payment_type\":\"payment\",\"created_at\":\"2025-01-02\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let events = buildInvoiceTimeline(from: inv)
        let hasPay = events.contains { if case .paymentRecorded = $0 { return true }; return false }
        XCTAssertTrue(hasPay)
    }

    func test_timeline_withRefundPayment_includesRefundEvent() {
        let paymentsJSON = "[{\"id\":1,\"amount\":10.0,\"method\":\"cash\",\"payment_type\":\"refund\",\"created_at\":\"2025-01-03\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let events = buildInvoiceTimeline(from: inv)
        let hasRefund = events.contains { if case .refundIssued = $0 { return true }; return false }
        XCTAssertTrue(hasRefund)
    }

    func test_timeline_payment_amountConvertedToCents() {
        let paymentsJSON = "[{\"id\":1,\"amount\":12.50,\"payment_type\":\"payment\",\"created_at\":\"2025-01-02\"}]"
        let inv = invoice(paymentsJSON: paymentsJSON)
        let events = buildInvoiceTimeline(from: inv)
        let payEvent = events.first { if case .paymentRecorded = $0 { return true }; return false }
        guard case let .paymentRecorded(_, cents, _, _) = payEvent else {
            XCTFail("No payment event")
            return
        }
        XCTAssertEqual(cents, 1250)
    }

    // MARK: - Void event

    func test_timeline_voidStatus_includesVoidEvent() {
        let inv = invoice(status: "void", updatedAt: "2025-01-05T12:00:00Z")
        let events = buildInvoiceTimeline(from: inv)
        let hasVoid = events.contains { if case .voided = $0 { return true }; return false }
        XCTAssertTrue(hasVoid)
    }

    func test_timeline_nonVoidStatus_noVoidEvent() {
        let inv = invoice(status: "paid")
        let events = buildInvoiceTimeline(from: inv)
        let hasVoid = events.contains { if case .voided = $0 { return true }; return false }
        XCTAssertFalse(hasVoid)
    }

    // MARK: - Notes event

    func test_timeline_withNotes_includesNotedEvent() {
        let inv = invoice(notes: "Customer wants white case")
        let events = buildInvoiceTimeline(from: inv)
        let hasNoted = events.contains { if case .noted = $0 { return true }; return false }
        XCTAssertTrue(hasNoted)
    }

    func test_timeline_withoutNotes_noNotedEvent() {
        let inv = invoice()
        let events = buildInvoiceTimeline(from: inv)
        let hasNoted = events.contains { if case .noted = $0 { return true }; return false }
        XCTAssertFalse(hasNoted)
    }

    // MARK: - Sort order

    func test_timeline_sortedDescendingByTimestamp() {
        let paymentsJSON = "[{\"id\":1,\"amount\":50.0,\"payment_type\":\"payment\",\"created_at\":\"2025-01-10\"}]"
        let inv = invoice(createdAt: "2025-01-01", paymentsJSON: paymentsJSON)
        let events = buildInvoiceTimeline(from: inv)
        // First event should be the later payment (2025-01-10 > 2025-01-01)
        XCTAssertTrue(events[0].timestamp >= events.last!.timestamp)
    }

    // MARK: - uniqueId

    func test_timelineEventId_createdIsUnique() {
        let inv = invoice()
        let events = buildInvoiceTimeline(from: inv)
        let ids = events.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "All timeline event IDs must be unique")
    }
}
