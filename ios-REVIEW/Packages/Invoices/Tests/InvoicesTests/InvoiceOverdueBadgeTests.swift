import XCTest
@testable import Invoices
import Networking

// §7.5 Overdue automation — overdue badge + deep-link wiring tests

// MARK: - Stub repository

private final class StubOverdueRepo: InvoiceRepository, @unchecked Sendable {
    var stubbedInvoices: [InvoiceSummary] = []

    func list(filter: InvoiceFilter, keyword: String?) async throws -> [InvoiceSummary] {
        stubbedInvoices
    }

    func listExtended(
        statusTab: InvoiceStatusTab,
        keyword: String?,
        sort: InvoiceSortOption,
        cursor: String?,
        advancedFilter: InvoiceListFilter
    ) async throws -> InvoicesListResponse {
        InvoicesListResponse(invoices: stubbedInvoices, pagination: nil)
    }
}

// MARK: - InvoiceListViewModel overdueCount tests

@MainActor
final class InvoiceOverdueBadgeTests: XCTestCase {

    // MARK: - overdueCount

    func test_overdueCount_zero_when_no_invoices() {
        let repo = StubOverdueRepo()
        let vm = InvoiceListViewModel(repo: repo)
        XCTAssertEqual(vm.overdueCount, 0)
    }

    func test_overdueCount_counts_only_overdue_status() async {
        let repo = StubOverdueRepo()
        repo.stubbedInvoices = [
            makeInvoice(id: 1, status: "overdue"),
            makeInvoice(id: 2, status: "paid"),
            makeInvoice(id: 3, status: "overdue"),
            makeInvoice(id: 4, status: "unpaid"),
        ]
        let vm = InvoiceListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.overdueCount, 2)
    }

    func test_overdueCount_case_insensitive() async {
        let repo = StubOverdueRepo()
        repo.stubbedInvoices = [
            makeInvoice(id: 1, status: "OVERDUE"),
            makeInvoice(id: 2, status: "Overdue"),
        ]
        let vm = InvoiceListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.overdueCount, 2)
    }

    func test_overdueCount_zero_when_all_paid() async {
        let repo = StubOverdueRepo()
        repo.stubbedInvoices = [
            makeInvoice(id: 1, status: "paid"),
            makeInvoice(id: 2, status: "paid"),
        ]
        let vm = InvoiceListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.overdueCount, 0)
    }

    func test_overdueCount_nil_status_not_counted() async {
        let repo = StubOverdueRepo()
        repo.stubbedInvoices = [
            makeInvoice(id: 1, status: nil),
            makeInvoice(id: 2, status: "overdue"),
        ]
        let vm = InvoiceListViewModel(repo: repo)
        await vm.load()
        XCTAssertEqual(vm.overdueCount, 1)
    }

    // MARK: - Deep-link notification

    func test_invoiceDeepLinkNavigate_notificationName_is_stable() {
        XCTAssertEqual(
            Notification.Name.invoiceDeepLinkNavigate.rawValue,
            "com.bizarrecrm.invoice.deepLinkNavigate"
        )
    }

    func test_handleRoute_posts_notification_with_correct_invoiceId() {
        let expectation = XCTestExpectation(description: "Notification received")
        let expectedId: Int64 = 42

        let observer = NotificationCenter.default.addObserver(
            forName: .invoiceDeepLinkNavigate,
            object: nil,
            queue: .main
        ) { note in
            let receivedId = note.userInfo?["invoiceId"] as? Int64
            XCTAssertEqual(receivedId, expectedId)
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Task { @MainActor in
            InvoiceDeepLinkHandler.handleRoute(invoiceId: expectedId)
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func test_handleRoute_posts_different_ids_independently() {
        var receivedIds: [Int64] = []
        let expectation = XCTestExpectation(description: "Two notifications")
        expectation.expectedFulfillmentCount = 2

        let observer = NotificationCenter.default.addObserver(
            forName: .invoiceDeepLinkNavigate,
            object: nil,
            queue: .main
        ) { note in
            if let id = note.userInfo?["invoiceId"] as? Int64 {
                receivedIds.append(id)
            }
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        Task { @MainActor in
            InvoiceDeepLinkHandler.handleRoute(invoiceId: 10)
            InvoiceDeepLinkHandler.handleRoute(invoiceId: 20)
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(Set(receivedIds), [10, 20])
    }
}

// MARK: - Helpers

/// Decode an `InvoiceSummary` from a JSON dictionary so we don't depend on
/// a memberwise init (the struct uses CodingKeys only).
private func makeInvoice(id: Int64, status: String?) -> InvoiceSummary {
    var dict: [String: Any] = [
        "id": id,
        "order_id": "INV-\(id)",
        "customer_id": 1,
        "first_name": "Test",
        "last_name": "Customer",
        "total": 100.0,
        "amount_paid": 0.0,
        "amount_due": 100.0,
        "created_at": "2026-04-01T00:00:00Z",
        "due_on": "2026-03-01T00:00:00Z",
    ]
    if let status { dict["status"] = status }
    let data = try! JSONSerialization.data(withJSONObject: dict)
    return try! JSONDecoder().decode(InvoiceSummary.self, from: data)
}
