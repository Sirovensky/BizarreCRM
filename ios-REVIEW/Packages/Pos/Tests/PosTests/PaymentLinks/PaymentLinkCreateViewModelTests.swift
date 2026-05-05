#if canImport(UIKit)
import XCTest
@testable import Pos
import Networking

// MARK: - §41 PaymentLinkCreateViewModel — Unit Tests

@MainActor
final class PaymentLinkCreateViewModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_defaultsTo7DayExpiry() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        XCTAssertEqual(vm.expiryDays, 7)
    }

    func test_initialState_emptyAmountTextWhenNoPrefill() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        XCTAssertEqual(vm.amountText, "")
        XCTAssertEqual(vm.parsedAmountCents, 0)
    }

    func test_initialState_prefillAmountCentsConvertsToDecimalText() {
        let vm = PaymentLinkCreateViewModel(
            api: StubCreateAPIClient(),
            prefillAmountCents: 1999
        )
        XCTAssertEqual(vm.amountText, "19.99")
    }

    func test_initialState_prefillInvoiceIdPopulatesTextField() {
        let vm = PaymentLinkCreateViewModel(
            api: StubCreateAPIClient(),
            invoiceId: 42
        )
        XCTAssertEqual(vm.invoiceIdText, "42")
    }

    func test_initialState_phaseIsEditing() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        XCTAssertEqual(vm.phase, .editing)
    }

    // MARK: - parsedAmountCents

    func test_parsedAmountCents_validDollarString() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "19.99"
        XCTAssertEqual(vm.parsedAmountCents, 1999)
    }

    func test_parsedAmountCents_roundsHalfUp() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        // 10.005 → rounds to 1001 (toFixed(2) → 10.01 → * 100 = 1001)
        vm.amountText = "10.005"
        XCTAssertEqual(vm.parsedAmountCents, 1001)
    }

    func test_parsedAmountCents_zero_returnsZero() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "0"
        XCTAssertEqual(vm.parsedAmountCents, 0)
    }

    func test_parsedAmountCents_negative_returnsZero() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "-5.00"
        XCTAssertEqual(vm.parsedAmountCents, 0)
    }

    func test_parsedAmountCents_garbage_returnsZero() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "abc"
        XCTAssertEqual(vm.parsedAmountCents, 0)
    }

    func test_parsedAmountCents_empty_returnsZero() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = ""
        XCTAssertEqual(vm.parsedAmountCents, 0)
    }

    func test_parsedAmountCents_largeAmount() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "9999.99"
        XCTAssertEqual(vm.parsedAmountCents, 999999)
    }

    // MARK: - canCreate

    func test_canCreate_falseWhenAmountZero() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = ""
        XCTAssertFalse(vm.canCreate)
    }

    func test_canCreate_trueWhenAmountPositive() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "25.00"
        XCTAssertTrue(vm.canCreate)
    }

    // MARK: - amountHint

    func test_amountHint_nilWhenEmpty() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = ""
        XCTAssertNil(vm.amountHint)
    }

    func test_amountHint_nonNilWhenValidAmount() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "25.00"
        XCTAssertNotNil(vm.amountHint)
    }

    func test_amountHint_showsValidationHintForBadInput() {
        let vm = PaymentLinkCreateViewModel(api: StubCreateAPIClient())
        vm.amountText = "bad"
        XCTAssertNotNil(vm.amountHint)
        XCTAssertTrue(vm.amountHint?.contains("valid") == true)
    }

    // MARK: - create() — success

    func test_create_success_transitionsToReadyPhase() async {
        let stub = StubCreateAPIClient()
        let result = makeLink(id: 10)
        stub.createResult = .success(result)

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "30.00"
        await vm.create()

        if case .ready(let link) = vm.phase {
            XCTAssertEqual(link.id, 10)
        } else {
            XCTFail("Expected .ready phase, got \(vm.phase)")
        }
    }

    func test_create_success_setsCreatedLink() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink(id: 20))

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "50.00"
        await vm.create()

        XCTAssertNotNil(vm.createdLink)
        XCTAssertEqual(vm.createdLink?.id, 20)
    }

    func test_create_success_clearsError() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        await vm.create()

        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - create() — passes invoice ID

    func test_create_passesPresetInvoiceId() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(
            api: stub,
            invoiceId: 99
        )
        vm.amountText = "10.00"
        await vm.create()

        XCTAssertEqual(stub.capturedRequest?.invoiceId, 99)
    }

    func test_create_passesTypedInvoiceId() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        vm.invoiceIdText = "55"
        await vm.create()

        XCTAssertEqual(stub.capturedRequest?.invoiceId, 55)
    }

    func test_create_ignoresInvalidInvoiceIdText() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub, invoiceId: 11)
        vm.amountText = "10.00"
        vm.invoiceIdText = "bad"      // invalid → falls back to preset
        await vm.create()

        XCTAssertEqual(stub.capturedRequest?.invoiceId, 11)
    }

    // MARK: - create() — failure

    func test_create_failure_setsErrorAndResetsToEditing() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .failure(URLError(.badServerResponse))

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        await vm.create()

        XCTAssertEqual(vm.phase, .editing)
        XCTAssertNotNil(vm.errorMessage)
    }

    // MARK: - create() — idempotent when already creating

    func test_create_doesNotDoubleSubmitWhenAlreadyCreating() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        // First call is awaited sequentially so by the time we check,
        // the phase is .ready. The guard in create() prevents re-entry.
        await vm.create()
        // A second call on .ready phase must be a no-op.
        let callCountBefore = stub.createCallCount
        await vm.create()
        XCTAssertEqual(stub.createCallCount, callCountBefore)
    }

    // MARK: - create() — description trimmed

    func test_create_trimsWhitespaceFromDescription() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        vm.description = "   Hello world   "
        await vm.create()

        XCTAssertEqual(stub.capturedRequest?.description, "Hello world")
    }

    func test_create_sendsNilDescriptionWhenBlank() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        vm.description = "   "
        await vm.create()

        XCTAssertNil(stub.capturedRequest?.description)
    }

    // MARK: - Expiry ISO string

    func test_expiryISO_appliedFromExpiryDays() async {
        let stub = StubCreateAPIClient()
        stub.createResult = .success(makeLink())

        let vm = PaymentLinkCreateViewModel(api: stub)
        vm.amountText = "10.00"
        vm.expiryDays = 14
        await vm.create()

        guard let expiresAt = stub.capturedRequest?.expiresAt else {
            XCTFail("Expected expiresAt to be set"); return
        }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let parsed = fmt.date(from: expiresAt)
        XCTAssertNotNil(parsed, "expiresAt should be valid ISO-8601: \(expiresAt)")
        // 14 days ahead, allow ±60 s clock slack.
        let delta = (parsed?.timeIntervalSinceNow ?? 0)
        XCTAssertGreaterThan(delta, 14 * 86_400 - 60)
        XCTAssertLessThan(delta, 14 * 86_400 + 60)
    }

    // MARK: - Helpers

    private func makeLink(
        id: Int64 = 1,
        amountCents: Int = 1000
    ) -> PaymentLink {
        PaymentLink(
            id: id,
            shortId: "tok-create",
            url: "https://shop.example.com/pay/tok-create",
            status: "active",
            amountCents: amountCents,
            createdAt: "2026-04-22T12:00:00Z",
            expiresAt: "2026-04-29T12:00:00Z",
            paidAt: nil
        )
    }
}

// MARK: - StubCreateAPIClient

/// Records the last `createPaymentLink` call so tests can assert on the request body.
private final class StubCreateAPIClient: APIClient, @unchecked Sendable {
    var createResult: Result<PaymentLink, Error> = .success(
        PaymentLink(
            id: 1,
            shortId: "stub",
            url: "https://shop.example.com/pay/stub",
            status: "active",
            amountCents: 1000,
            createdAt: nil,
            expiresAt: nil,
            paidAt: nil
        )
    )
    private(set) var capturedRequest: CreatePaymentLinkRequest?
    private(set) var createCallCount: Int = 0

    func get<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> T {
        // Called by createPaymentLink → getPaymentLink after create.
        if T.self == PaymentLink.self {
            switch createResult {
            case .success(let l): return l as! T  // swiftlint:disable:this force_cast
            case .failure(let e): throw e
            }
        }
        throw URLError(.notConnectedToInternet)
    }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String,
        body: B,
        as type: T.Type
    ) async throws -> T {
        createCallCount += 1
        // Capture the encoded request for assertion.
        if let req = body as? CreatePaymentLinkRequest {
            capturedRequest = req
        }
        switch createResult {
        case .success(let link):
            // The real `createPaymentLink` POSTs to get CreatePaymentLinkResponse,
            // then does a GET. Here we simulate the POST returning the stub token/id.
            if T.self == CreatePaymentLinkResponse.self {
                // swiftlint:disable:next force_cast
                return CreatePaymentLinkResponse(id: link.id, token: link.shortId ?? "stub") as! T
            }
            throw URLError(.notConnectedToInternet)
        case .failure(let e):
            throw e
        }
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.notConnectedToInternet) }

    func delete(_ path: String) async throws {
        throw URLError(.notConnectedToInternet)
    }

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem]?,
        as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.notConnectedToInternet) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { URL(string: "https://shop.example.com/api/v1") }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
