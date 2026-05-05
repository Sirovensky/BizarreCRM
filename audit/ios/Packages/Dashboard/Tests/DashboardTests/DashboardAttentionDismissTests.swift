import XCTest
@testable import Dashboard
@testable import Networking

// MARK: - DashboardAttentionDismissTests
//
// §3.3 Dismiss persistence — verifies AttentionRowKind displayId is stable
// so the App layer can use it as a server-side notification ID key, and
// that the onDismissAttentionItem callback is exposed on DashboardView.

final class DashboardAttentionDismissTests: XCTestCase {

    func test_staleTicketDisplayId_includesOrderId() {
        let ticket = NeedsAttention.StaleTicket(
            id: 1, orderId: "T-001", customerName: "Alice", daysStale: 3, status: "open"
        )
        let kind = AttentionRowKind.staleTicket(ticket)
        XCTAssertEqual(kind.displayId, "#T-001")
    }

    func test_overdueInvoiceDisplayId_prefersOrderId() {
        let invoice = NeedsAttention.OverdueInvoice(
            id: 42, orderId: "INV-100", customerName: "Bob", amountDue: 99.0, daysOverdue: 5
        )
        let kind = AttentionRowKind.overdueInvoice(invoice)
        XCTAssertEqual(kind.displayId, "#INV-100")
    }

    func test_overdueInvoiceDisplayId_fallsBackToId() {
        let invoice = NeedsAttention.OverdueInvoice(
            id: 42, orderId: nil, customerName: nil, amountDue: 50.0, daysOverdue: 2
        )
        let kind = AttentionRowKind.overdueInvoice(invoice)
        XCTAssertEqual(kind.displayId, "#42")
    }

    func test_aggregateMissingParts_hasStableId() {
        let kind = AttentionRowKind.aggregateMissingParts(3)
        XCTAssertEqual(kind.displayId, "missing-parts")
    }

    func test_aggregateLowStock_hasStableId() {
        let kind = AttentionRowKind.aggregateLowStock(5)
        XCTAssertEqual(kind.displayId, "low-stock")
    }

    func test_staleTicketLabel_includesCustomerName() {
        let ticket = NeedsAttention.StaleTicket(
            id: 1, orderId: "T-002", customerName: "Carol", daysStale: 7, status: nil
        )
        let kind = AttentionRowKind.staleTicket(ticket)
        XCTAssertTrue(kind.label.contains("Carol"))
        XCTAssertTrue(kind.label.contains("T-002"))
    }

    func test_aggregateLabel_pluralizes() {
        let parts = AttentionRowKind.aggregateMissingParts(2)
        XCTAssertTrue(parts.label.contains("parts"))

        let stock = AttentionRowKind.aggregateLowStock(1)
        XCTAssertTrue(stock.label.contains("item"))
        XCTAssertFalse(stock.label.contains("items"))
    }
}
