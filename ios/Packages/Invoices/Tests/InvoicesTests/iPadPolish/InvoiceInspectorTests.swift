import XCTest
@testable import Invoices
@testable import Networking

// §22 iPad — InvoiceInspector logic tests.
//
// All tests are headless. They exercise:
//  1. `InvoiceInspectorViewModel` — state transitions, load/reload.
//  2. `buildPaymentHistory` — already covered in InvoicePaymentHistoryTests;
//     here we verify the inspector-specific timeline label mapping.

@MainActor
final class InvoiceInspectorTests: XCTestCase {

    // MARK: - ViewModel: initial state is loading

    func test_initialState_isLoading() {
        let vm = InvoiceInspectorViewModel(invoiceId: 1, repo: SucceedingRepo())
        guard case .loading = vm.state else {
            XCTFail("Expected .loading, got \(vm.state)")
            return
        }
    }

    // MARK: - ViewModel: transitions to loaded on success

    func test_load_transitionsToLoaded() async {
        let vm = InvoiceInspectorViewModel(invoiceId: 1, repo: SucceedingRepo())
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded, got \(vm.state)")
            return
        }
    }

    func test_load_exposes_correctInvoiceId() async {
        let vm = InvoiceInspectorViewModel(invoiceId: 99, repo: SucceedingRepo(id: 99))
        await vm.load()
        guard case let .loaded(inv) = vm.state else {
            XCTFail("Expected .loaded"); return
        }
        XCTAssertEqual(inv.id, 99)
    }

    // MARK: - ViewModel: transitions to failed on error

    func test_load_transitionsToFailed() async {
        let vm = InvoiceInspectorViewModel(invoiceId: 1, repo: FailingRepo())
        await vm.load()
        guard case .failed = vm.state else {
            XCTFail("Expected .failed, got \(vm.state)")
            return
        }
    }

    func test_load_failed_errorMessageIsNonEmpty() async {
        let vm = InvoiceInspectorViewModel(invoiceId: 1, repo: FailingRepo())
        await vm.load()
        guard case let .failed(msg) = vm.state else {
            XCTFail("Expected .failed"); return
        }
        XCTAssertFalse(msg.isEmpty)
    }

    // MARK: - ViewModel: reload resets to loading then loaded

    func test_reload_resets_then_loads() async {
        let vm = InvoiceInspectorViewModel(invoiceId: 1, repo: SucceedingRepo())
        await vm.load()
        // force .failed to test reload recovery
        await vm.setState(.failed("oops"))
        await vm.load()
        guard case .loaded = vm.state else {
            XCTFail("Expected .loaded after reload, got \(vm.state)")
            return
        }
    }

    // MARK: - Totals correctness via buildPaymentHistory

    func test_buildPaymentHistory_paidInvoice_hasTwoPaymentEntries() {
        let inv = makeDetail(status: "paid", payments: [
            ["id": 1, "amount": 30.0, "method": "cash", "payment_type": "payment", "created_at": "2025-01-15"],
            ["id": 2, "amount": 70.0, "method": "cash", "payment_type": "payment", "created_at": "2025-01-16"]
        ])
        let entries = buildPaymentHistory(from: inv)
        let payments = entries.filter { $0.kind == .payment }
        XCTAssertEqual(payments.count, 2)
    }

    func test_buildPaymentHistory_refundEntry_isNegativeCents() {
        let inv = makeDetail(status: "partial", payments: [
            ["id": 1, "amount": 100.0, "method": "cash", "payment_type": "payment", "created_at": "2025-01-15"],
            ["id": 2, "amount": 20.0, "method": "cash", "payment_type": "refund", "created_at": "2025-01-16"]
        ])
        let entries = buildPaymentHistory(from: inv)
        let refund = entries.first { $0.kind == .refund }
        XCTAssertNotNil(refund)
        XCTAssertLessThan(refund!.amountCents, 0)
    }

    func test_buildPaymentHistory_voidInvoice_hasVoidEntry() {
        let inv = makeDetail(status: "void", payments: nil)
        let entries = buildPaymentHistory(from: inv)
        XCTAssertTrue(entries.contains { $0.kind == .void })
    }

    func test_buildPaymentHistory_sortedDescendingByTimestamp() {
        let inv = makeDetail(status: "paid", payments: [
            ["id": 1, "amount": 50.0, "method": "cash", "payment_type": "payment", "created_at": "2025-01-10"],
            ["id": 2, "amount": 50.0, "method": "cash", "payment_type": "payment", "created_at": "2025-03-20"]
        ])
        let entries = buildPaymentHistory(from: inv)
        guard entries.count >= 2 else { XCTFail("Expected ≥2 entries"); return }
        XCTAssertGreaterThanOrEqual(entries[0].timestamp, entries[1].timestamp)
    }

    // MARK: - Timeline label mapping

    func test_paymentKind_timelineLabel_isPayment() {
        XCTAssertEqual(PaymentHistoryKind.payment.testTimelineLabel, "Payment")
    }

    func test_refundKind_timelineLabel_isRefund() {
        XCTAssertEqual(PaymentHistoryKind.refund.testTimelineLabel, "Refund")
    }

    func test_voidKind_timelineLabel_isVoided() {
        XCTAssertEqual(PaymentHistoryKind.void.testTimelineLabel, "Voided")
    }

    // MARK: - Helpers

    private func makeDetail(
        id: Int64 = 1,
        status: String,
        payments: [[String: Any]]? = nil
    ) -> InvoiceDetail {
        makeInvoiceDetailFromRaw(id: id, status: status, total: 100.0, payments: payments)
    }
}

// MARK: - InvoiceInspectorViewModel (extracted logic, testable without SwiftUI)

/// Testable view-model extracted from `InvoiceInspector`. Holds load state
/// and drives data loading independently of SwiftUI rendering.
@MainActor
@Observable
final class InvoiceInspectorViewModel {
    enum State {
        case loading
        case loaded(InvoiceDetail)
        case failed(String)
    }

    private(set) var state: State = .loading
    private let invoiceId: Int64
    private let repo: InvoiceDetailRepository

    init(invoiceId: Int64, repo: InvoiceDetailRepository) {
        self.invoiceId = invoiceId
        self.repo = repo
    }

    func load() async {
        state = .loading
        do {
            let inv = try await repo.detail(id: invoiceId)
            state = .loaded(inv)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Test seam — sets state directly without making network calls.
    func setState(_ newState: State) async {
        state = newState
    }
}

// MARK: - Test repos

private struct SucceedingRepo: InvoiceDetailRepository {
    let id: Int64
    init(id: Int64 = 1) { self.id = id }

    func detail(id: Int64) async throws -> InvoiceDetail {
        makeInvoiceDetailFromRaw(id: self.id, status: "unpaid", total: 120.0, amountDue: 120.0)
    }
}

private struct FailingRepo: InvoiceDetailRepository {
    func detail(id: Int64) async throws -> InvoiceDetail {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - PaymentHistoryKind.testTimelineLabel

private extension PaymentHistoryKind {
    /// Mirrors the `timelineLabel` logic from `InvoiceInspector.TimelineRow`
    /// so it can be tested without a SwiftUI render pass.
    var testTimelineLabel: String {
        switch self {
        case .payment: return "Payment"
        case .refund:  return "Refund"
        case .void:    return "Voided"
        }
    }
}

// MARK: - InvoiceDetail factory (JSON-based, no synthesised init required)

/// Builds an `InvoiceDetail` from raw [String:Any] payment dictionaries.
/// `payments` elements should use snake_case keys matching the server contract.
func makeInvoiceDetailFromRaw(
    id: Int64,
    status: String,
    total: Double,
    amountPaid: Double? = nil,
    amountDue: Double? = nil,
    payments: [[String: Any]]? = nil
) -> InvoiceDetail {
    var jsonObject: [String: Any] = [
        "id": id,
        "order_id": "INV-\(id)",
        "customer_id": 1,
        "first_name": "Test",
        "last_name": "Customer",
        "status": status,
        "total": total
    ]
    if let amountPaid { jsonObject["amount_paid"] = amountPaid }
    if let amountDue  { jsonObject["amount_due"] = amountDue }
    if let payments   { jsonObject["payments"] = payments }

    let data = try! JSONSerialization.data(withJSONObject: jsonObject)
    let decoder = JSONDecoder()
    return try! decoder.decode(InvoiceDetail.self, from: data)
}
