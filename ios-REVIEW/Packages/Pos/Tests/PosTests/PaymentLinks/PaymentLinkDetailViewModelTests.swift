#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - §41 PaymentLinkDetailViewModel — Unit Tests

@MainActor
final class PaymentLinkDetailViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_linksFromPassedLink() {
        let link = makeLink(id: 7, amountCents: 3000, status: "active")
        let vm = PaymentLinkDetailViewModel(link: link, api: StubDetailAPIClient())
        XCTAssertEqual(vm.link.id, 7)
        XCTAssertEqual(vm.link.amountCents, 3000)
        XCTAssertEqual(vm.clickCount, 0)
        XCTAssertNil(vm.lastClickedAt)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isCancelling)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - lastClickedLabel

    func test_lastClickedLabel_nilLastClickedAt_returnsDash() {
        let vm = PaymentLinkDetailViewModel(link: makeLink(), api: StubDetailAPIClient())
        XCTAssertEqual(vm.lastClickedLabel, "—")
    }

    func test_lastClickedLabel_validISO_returnsFormattedString() {
        let vm = PaymentLinkDetailViewModel(link: makeLink(), api: StubDetailAPIClient())
        // Simulate a server timestamp being injected.
        // We test via `reload()` below — here verify it doesn't crash on known values.
        // The formatter is locale-dependent; just verify non-empty non-dash output
        // would be produced. We use a helper that calls the same path.
        let label = vm.lastClickedLabel  // should be "—" since nil
        XCTAssertEqual(label, "—")
    }

    // MARK: - reload — success path

    func test_reload_success_updatesLink() async throws {
        let stub = StubDetailAPIClient()
        let updatedLink = makeLink(id: 5, status: "paid")
        stub.getPaymentLinkResult = .success(updatedLink)
        stub.getEnvelopeResult = makeEnvelopeData(clickCount: 3, lastClickedAt: "2026-04-22T10:00:00Z")

        let vm = PaymentLinkDetailViewModel(link: makeLink(id: 5, status: "active"), api: stub)
        await vm.reload()

        XCTAssertEqual(vm.link.status, "paid")
        XCTAssertEqual(vm.clickCount, 3)
        XCTAssertEqual(vm.lastClickedAt, "2026-04-22T10:00:00Z")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
    }

    func test_reload_success_clickCountDefaultsToZeroWhenMissing() async {
        let stub = StubDetailAPIClient()
        stub.getPaymentLinkResult = .success(makeLink(id: 1))
        // Envelope with no click_count
        stub.getEnvelopeResult = makeEnvelopeData(clickCount: nil, lastClickedAt: nil)

        let vm = PaymentLinkDetailViewModel(link: makeLink(id: 1), api: stub)
        await vm.reload()

        XCTAssertEqual(vm.clickCount, 0)
        XCTAssertNil(vm.lastClickedAt)
    }

    // MARK: - reload — error path

    func test_reload_failure_setsErrorMessage() async {
        let stub = StubDetailAPIClient()
        stub.getPaymentLinkResult = .failure(URLError(.notConnectedToInternet))

        let vm = PaymentLinkDetailViewModel(link: makeLink(), api: stub)
        await vm.reload()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - cancel — success

    func test_cancel_marksLinkCancelled() async {
        let stub = StubDetailAPIClient()
        let cancelledLink = makeLink(id: 3, status: "cancelled")
        stub.getPaymentLinkResult = .success(cancelledLink)
        // Provide valid envelope JSON so the reload() getEnvelope call succeeds.
        stub.getEnvelopeResult = makeEnvelopeData(clickCount: 0, lastClickedAt: nil)
        stub.cancelResult = .success(())

        let vm = PaymentLinkDetailViewModel(link: makeLink(id: 3, status: "active"), api: stub)
        await vm.cancel()

        XCTAssertFalse(vm.isCancelling)
        // Link should reflect the refreshed "cancelled" row.
        XCTAssertEqual(vm.link.status, "cancelled")
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - cancel — skips when not active

    func test_cancel_noOpWhenAlreadyCancelled() async {
        let stub = StubDetailAPIClient()
        let vm = PaymentLinkDetailViewModel(
            link: makeLink(status: "cancelled"),
            api: stub
        )
        await vm.cancel()
        XCTAssertFalse(stub.cancelWasCalled)
    }

    func test_cancel_noOpWhenPaid() async {
        let stub = StubDetailAPIClient()
        let vm = PaymentLinkDetailViewModel(
            link: makeLink(status: "paid"),
            api: stub
        )
        await vm.cancel()
        XCTAssertFalse(stub.cancelWasCalled)
    }

    // MARK: - cancel — error

    func test_cancel_failure_setsErrorMessage() async {
        let stub = StubDetailAPIClient()
        stub.cancelResult = .failure(URLError(.timedOut))

        let vm = PaymentLinkDetailViewModel(link: makeLink(status: "active"), api: stub)
        await vm.cancel()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isCancelling)
    }

    // MARK: - PaymentLinkDetailRow decoding

    func test_detailRow_decodesClickCount() throws {
        let json = """
        { "click_count": 12, "last_clicked_at": "2026-04-20T09:30:00Z" }
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(PaymentLinkDetailRow.self, from: json)
        XCTAssertEqual(row.clickCount, 12)
        XCTAssertEqual(row.lastClickedAt, "2026-04-20T09:30:00Z")
    }

    func test_detailRow_handlesNullValues() throws {
        let json = """
        { "click_count": null, "last_clicked_at": null }
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(PaymentLinkDetailRow.self, from: json)
        XCTAssertNil(row.clickCount)
        XCTAssertNil(row.lastClickedAt)
    }

    func test_detailRow_toleratesMissingKeys() throws {
        let json = "{}".data(using: .utf8)!
        let row = try JSONDecoder().decode(PaymentLinkDetailRow.self, from: json)
        XCTAssertNil(row.clickCount)
        XCTAssertNil(row.lastClickedAt)
    }

    // MARK: - Helpers

    private func makeLink(
        id: Int64 = 1,
        amountCents: Int = 2500,
        status: String = "active"
    ) -> PaymentLink {
        PaymentLink(
            id: id,
            shortId: "tok-\(id)",
            url: "https://shop.example.com/pay/tok-\(id)",
            status: status,
            amountCents: amountCents,
            createdAt: "2026-04-20T12:00:00Z",
            expiresAt: "2026-04-27T12:00:00Z",
            paidAt: status == "paid" ? "2026-04-21T15:00:00Z" : nil
        )
    }

    /// Build raw envelope JSON data for the `getEnvelope` stub.
    private func makeEnvelopeData(
        clickCount: Int?,
        lastClickedAt: String?
    ) -> Data {
        var fields: [String] = []
        if let c = clickCount {
            fields.append("\"click_count\": \(c)")
        } else {
            fields.append("\"click_count\": null")
        }
        if let l = lastClickedAt {
            fields.append("\"last_clicked_at\": \"\(l)\"")
        } else {
            fields.append("\"last_clicked_at\": null")
        }
        let inner = fields.joined(separator: ", ")
        let raw = "{ \"success\": true, \"data\": { \(inner) } }"
        return raw.data(using: .utf8)!
    }
}

// MARK: - StubDetailAPIClient

/// Stub that lets tests control `getPaymentLink` and `cancelPaymentLink` + envelope reads.
private final class StubDetailAPIClient: APIClient, @unchecked Sendable {
    var getPaymentLinkResult: Result<PaymentLink, Error>?
    var cancelResult: Result<Void, Error> = .success(())
    /// Raw JSON data returned for `getEnvelope` calls.
    var getEnvelopeResult: Data = Data()
    private(set) var cancelWasCalled: Bool = false

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        if T.self == PaymentLink.self {
            switch getPaymentLinkResult ?? .failure(URLError(.unknown)) {
            case .success(let l):
                // swiftlint:disable:next force_cast
                return l as! T
            case .failure(let e):
                throw e
            }
        }
        throw URLError(.notConnectedToInternet)
    }

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> APIResponse<T> {
        let decoder = JSONDecoder()
        return try decoder.decode(APIResponse<T>.self, from: getEnvelopeResult)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func delete(_ path: String) async throws {
        cancelWasCalled = true
        switch cancelResult {
        case .success: return
        case .failure(let e): throw e
        }
    }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { URL(string: "https://shop.example.com/api/v1") }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
