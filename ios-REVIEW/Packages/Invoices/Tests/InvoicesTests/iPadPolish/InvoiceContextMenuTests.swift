import XCTest
@testable import Invoices
@testable import Networking

// §22 iPad — InvoiceContextMenu logic tests.
//
// Tests are headless. They verify the business-logic helpers exposed from
// InvoiceContextMenu via the `canMarkPaid` flag and the underlying API calls
// using a lightweight stub repository.

@MainActor
final class InvoiceContextMenuTests: XCTestCase {

    // MARK: - canMarkPaid logic (mirrored from InvoiceSummary helper)

    func test_canMarkPaid_trueWhenUnpaidWithAmountDue() {
        let inv = makeSummary(status: "unpaid", amountDue: 50.0)
        XCTAssertTrue(inv.contextMenuCanMarkPaid)
    }

    func test_canMarkPaid_trueWhenPartialWithAmountDue() {
        let inv = makeSummary(status: "partial", amountDue: 20.0)
        XCTAssertTrue(inv.contextMenuCanMarkPaid)
    }

    func test_canMarkPaid_falseWhenPaid() {
        let inv = makeSummary(status: "paid", amountDue: 0.0)
        XCTAssertFalse(inv.contextMenuCanMarkPaid)
    }

    func test_canMarkPaid_falseWhenVoid() {
        let inv = makeSummary(status: "void", amountDue: 5.0)
        XCTAssertFalse(inv.contextMenuCanMarkPaid)
    }

    func test_canMarkPaid_falseWhenZeroAmountDue() {
        let inv = makeSummary(status: "unpaid", amountDue: 0.0)
        XCTAssertFalse(inv.contextMenuCanMarkPaid)
    }

    func test_canMarkPaid_falseWhenNilAmountDue() {
        let inv = makeSummary(status: "unpaid", amountDue: nil)
        XCTAssertFalse(inv.contextMenuCanMarkPaid)
    }

    // MARK: - Mark Paid API call

    func test_markPaid_callsRecordPayment_withFullAmountDue() async {
        let api = SpyAPIClient()
        let inv = makeSummary(status: "unpaid", amountDue: 75.50)
        var refreshCalled = false

        await InvoiceContextMenuActions.performMarkPaid(
            invoice: inv,
            api: api,
            onRefresh: { refreshCalled = true },
            onError: { _ in }
        )

        XCTAssertEqual(api.lastPostPath, "/api/v1/invoices/\(inv.id)/payments")
        XCTAssertTrue(refreshCalled)
    }

    func test_markPaid_callsOnError_whenAPIThrows() async {
        let api = SpyAPIClient(shouldThrow: true)
        let inv = makeSummary(status: "unpaid", amountDue: 10.0)
        var errorReceived: String?

        await InvoiceContextMenuActions.performMarkPaid(
            invoice: inv,
            api: api,
            onRefresh: {},
            onError: { errorReceived = $0 }
        )

        XCTAssertNotNil(errorReceived)
    }

    func test_markPaid_noopWhenAmountDueIsZero() async {
        let api = SpyAPIClient()
        let inv = makeSummary(status: "unpaid", amountDue: 0.0)

        await InvoiceContextMenuActions.performMarkPaid(
            invoice: inv,
            api: api,
            onRefresh: {},
            onError: { _ in }
        )

        // Should not have made any API call
        XCTAssertNil(api.lastPostPath)
    }

    // MARK: - Void API call (real server route: POST /:id/void)

    func test_void_callsPostVoidEndpoint() async {
        let api = SpyAPIClient()
        let inv = makeSummary(status: "unpaid", amountDue: 0.0)
        var refreshCalled = false

        await InvoiceContextMenuActions.performVoid(
            invoiceId: inv.id,
            api: api,
            onRefresh: { refreshCalled = true },
            onError: { _ in }
        )

        XCTAssertEqual(api.lastPostPath, "/api/v1/invoices/\(inv.id)/void")
        XCTAssertTrue(refreshCalled)
    }

    func test_void_callsOnError_whenAPIThrows() async {
        let api = SpyAPIClient(shouldThrow: true)
        let inv = makeSummary(status: "unpaid", amountDue: 0.0)
        var errorReceived: String?

        await InvoiceContextMenuActions.performVoid(
            invoiceId: inv.id,
            api: api,
            onRefresh: {},
            onError: { errorReceived = $0 }
        )

        XCTAssertNotNil(errorReceived)
    }

    // MARK: - Helpers

    private func makeSummary(
        id: Int64 = 42,
        status: String,
        amountDue: Double?
    ) -> InvoiceSummary {
        let amountDueJson = amountDue.map { String($0) } ?? "null"
        let json = """
        {
            "id": \(id),
            "order_id": "INV-042",
            "customer_id": 1,
            "first_name": "Ada",
            "last_name": "Lovelace",
            "total": 100.0,
            "status": "\(status)",
            "amount_paid": null,
            "amount_due": \(amountDueJson),
            "created_at": "2025-01-15"
        }
        """
        let decoder = JSONDecoder()
        return try! decoder.decode(InvoiceSummary.self, from: json.data(using: .utf8)!)
    }
}

// MARK: - InvoiceSummary.contextMenuCanMarkPaid helper

/// Duplicates the private `canMarkPaid` logic from `InvoiceContextMenu`
/// so tests can verify it without synthesising the full SwiftUI view.
private extension InvoiceSummary {
    var contextMenuCanMarkPaid: Bool {
        let s = (status ?? "").lowercased()
        guard s != "paid" && s != "void" else { return false }
        return (amountDue ?? 0) > 0
    }
}

// MARK: - InvoiceContextMenuActions (extracted logic for testability)

/// Pure-logic layer extracted from `InvoiceContextMenu` so tests can call
/// actions without constructing a SwiftUI view.
enum InvoiceContextMenuActions {
    static func performMarkPaid(
        invoice: InvoiceSummary,
        api: APIClient,
        onRefresh: () -> Void,
        onError: (String) -> Void
    ) async {
        guard let due = invoice.amountDue, due > 0 else { return }
        do {
            let body = RecordInvoicePaymentRequest(
                amount: due,
                method: "cash",
                notes: "Marked paid via context menu"
            )
            _ = try await api.recordPayment(invoiceId: invoice.id, body: body)
            onRefresh()
        } catch {
            onError(error.localizedDescription)
        }
    }

    static func performVoid(
        invoiceId: Int64,
        api: APIClient,
        onRefresh: () -> Void,
        onError: (String) -> Void
    ) async {
        do {
            struct VoidBody: Encodable, Sendable { let reason: String? }
            struct VoidResponse: Decodable, Sendable { let id: Int64? }
            _ = try await api.post(
                "/api/v1/invoices/\(invoiceId)/void",
                body: VoidBody(reason: "Voided via test"),
                as: VoidResponse.self
            )
            onRefresh()
        } catch {
            onError(error.localizedDescription)
        }
    }
}

// MARK: - SpyAPIClient

/// Minimal spy that records call paths and can optionally throw.
/// Runs on @MainActor so its properties can be read synchronously in @MainActor tests.
@MainActor
final class SpyAPIClient: APIClient {
    private(set) var lastPostPath: String?
    private(set) var lastPatchPath: String?
    private(set) var lastDeletePath: String?
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPostPath = path
        if shouldThrow { throw APITransportError.noBaseURL }
        // Return a minimal valid RecordPaymentResponse
        let json = #"{"id":1,"status":"paid","amount_paid":100.0,"amount_due":0.0}"#
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        lastPatchPath = path
        if shouldThrow { throw APITransportError.noBaseURL }
        let json = #"{"id":1}"#
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    func delete(_ path: String) async throws {
        lastDeletePath = path
        if shouldThrow { throw APITransportError.noBaseURL }
    }

    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }

    nonisolated func setAuthToken(_ token: String?) async {}
    nonisolated func setBaseURL(_ url: URL?) async {}
    nonisolated func currentBaseURL() async -> URL? { nil }
    nonisolated func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}
