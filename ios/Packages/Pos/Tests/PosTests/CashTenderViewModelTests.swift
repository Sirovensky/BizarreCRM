#if canImport(UIKit)
import XCTest
import Networking
@testable import Pos

/// §16.5 — Tests for `CashTenderViewModel`.
/// Verifies input filtering, change math, quick-amount helpers, and
/// phase transitions (entry → processing → changeDue / failed).
@MainActor
final class CashTenderViewModelTests: XCTestCase {

    // MARK: - Input filtering

    func test_updateInput_keepsDigitsAndDot() {
        let vm = makeVM(totalCents: 1000)
        vm.updateInput("12.34")
        XCTAssertEqual(vm.rawInput, "12.34")
    }

    func test_updateInput_stripsAlpha() {
        let vm = makeVM(totalCents: 1000)
        vm.updateInput("abc12.00xyz")
        XCTAssertEqual(vm.rawInput, "12.00")
    }

    func test_updateInput_stripsExtraDots() {
        let vm = makeVM(totalCents: 1000)
        vm.updateInput("12.3.4")
        XCTAssertEqual(vm.rawInput, "12.34")
    }

    func test_updateInput_stripsDollarSign() {
        let vm = makeVM(totalCents: 1000)
        vm.updateInput("$20.00")
        XCTAssertEqual(vm.rawInput, "20.00")
    }

    func test_updateInput_empty_givesEmptyInput() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "5.00"
        vm.updateInput("")
        XCTAssertEqual(vm.rawInput, "")
    }

    // MARK: - receivedCents

    func test_receivedCents_parsesCorrectly() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "20.00"
        XCTAssertEqual(vm.receivedCents, 2000)
    }

    func test_receivedCents_roundsHalfUp() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "10.005"
        XCTAssertEqual(vm.receivedCents, 1001)
    }

    func test_receivedCents_zero_whenEmpty() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = ""
        XCTAssertEqual(vm.receivedCents, 0)
    }

    // MARK: - changeCents

    func test_changeCents_exactAmount() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "10.00"
        XCTAssertEqual(vm.changeCents, 0)
    }

    func test_changeCents_overpayment() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "20.00"
        XCTAssertEqual(vm.changeCents, 1000)
    }

    func test_changeCents_underpayment_clampedToZero() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "5.00"
        XCTAssertEqual(vm.changeCents, 0)
    }

    // MARK: - canCharge

    func test_canCharge_trueWhenExact() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "10.00"
        XCTAssertTrue(vm.canCharge)
    }

    func test_canCharge_trueWhenOver() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "20.00"
        XCTAssertTrue(vm.canCharge)
    }

    func test_canCharge_falseWhenUnder() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "5.00"
        XCTAssertFalse(vm.canCharge)
    }

    func test_canCharge_falseWhenEmpty() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = ""
        XCTAssertFalse(vm.canCharge)
    }

    func test_canCharge_falseWhenProcessing() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "10.00"
        // Force processing phase manually.
        vm.phase = .processing
        XCTAssertFalse(vm.canCharge)
    }

    // MARK: - setExact

    func test_setExact_populatesInputWithTotal() {
        let vm = makeVM(totalCents: 1099)
        vm.setExact()
        XCTAssertEqual(vm.rawInput, "10.99")
        XCTAssertEqual(vm.receivedCents, 1099)
    }

    // MARK: - setRounded

    func test_setRounded_to5Dollars_roundsUpFrom1099() {
        let vm = makeVM(totalCents: 1099)
        vm.setRounded(to: 500)   // next multiple of $5 above $10.99 = $15
        XCTAssertEqual(vm.receivedCents, 1500)
    }

    func test_setRounded_exactMultiple_staysAtMultiple() {
        let vm = makeVM(totalCents: 1000)
        vm.setRounded(to: 500)   // $10 is already a multiple of $5
        XCTAssertEqual(vm.receivedCents, 1000)
    }

    func test_setRounded_to20Dollars() {
        let vm = makeVM(totalCents: 1500)
        vm.setRounded(to: 2000)   // next $20 above $15 = $20
        XCTAssertEqual(vm.receivedCents, 2000)
    }

    func test_setRounded_zeroRoundTo_noOp() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "5.00"
        vm.setRounded(to: 0)   // guard against divide-by-zero
        XCTAssertEqual(vm.rawInput, "5.00")   // unchanged
    }

    // MARK: - resetToEntry

    func test_resetToEntry_fromFailed() {
        let vm = makeVM(totalCents: 1000)
        vm.phase = .failed("network error")
        vm.resetToEntry()
        XCTAssertEqual(vm.phase, .entry)
    }

    // MARK: - charge() phase transitions

    func test_charge_success_transitionsToChangeDue() async {
        let api = PosTransactionMockAPIClient(
            result: .success(PosTransactionResponse(
                invoice: PosTransactionInvoice(id: 99, orderId: "ORD-1", totalCents: 1000),
                message: nil
            ))
        )
        let vm = makeVM(totalCents: 1000, api: api)
        vm.rawInput = "20.00"   // $20 tendered on $10 total
        await vm.charge()

        if case .changeDue(let r) = vm.phase {
            XCTAssertEqual(r.invoiceId, 99)
            XCTAssertEqual(r.orderId, "ORD-1")
            XCTAssertEqual(r.changeCents, 1000)   // $20 - $10
            XCTAssertEqual(r.receivedCents, 2000)
        } else {
            XCTFail("Expected .changeDue, got \(vm.phase)")
        }
    }

    func test_charge_exactAmount_zeroChange() async {
        let api = PosTransactionMockAPIClient(
            result: .success(PosTransactionResponse(
                invoice: PosTransactionInvoice(id: 1, orderId: nil, totalCents: 1000),
                message: nil
            ))
        )
        let vm = makeVM(totalCents: 1000, api: api)
        vm.rawInput = "10.00"
        await vm.charge()

        if case .changeDue(let r) = vm.phase {
            XCTAssertEqual(r.changeCents, 0)
        } else {
            XCTFail("Expected .changeDue, got \(vm.phase)")
        }
    }

    func test_charge_networkFailure_transitionsToFailed() async {
        let api = PosTransactionMockAPIClient(
            result: .failure(URLError(.notConnectedToInternet))
        )
        let vm = makeVM(totalCents: 1000, api: api)
        vm.rawInput = "10.00"
        await vm.charge()

        if case .failed(let msg) = vm.phase {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("Expected .failed, got \(vm.phase)")
        }
    }

    func test_charge_withCannotCharge_doesNothing() async {
        let api = PosTransactionMockAPIClient(
            result: .failure(URLError(.badURL))
        )
        let vm = makeVM(totalCents: 1000, api: api)
        vm.rawInput = "5.00"   // under total
        await vm.charge()
        XCTAssertEqual(vm.phase, .entry)   // unchanged
    }

    // MARK: - changeFormatted

    func test_changeFormatted_nonzero() {
        let vm = makeVM(totalCents: 1000)
        vm.rawInput = "15.00"
        XCTAssertFalse(vm.changeFormatted.isEmpty)
    }

    // MARK: - Helpers

    private func makeVM(
        totalCents: Int,
        api: APIClient? = nil
    ) -> CashTenderViewModel {
        let req = PosTransactionRequest(
            items: [PosTransactionLineItem(inventoryItemId: 1, quantity: 1)],
            paymentMethod: "cash",
            paymentAmount: Double(totalCents) / 100.0,
            idempotencyKey: UUID().uuidString
        )
        let resolvedApi = api ?? PosTransactionMockAPIClient(
            result: .success(PosTransactionResponse(
                invoice: PosTransactionInvoice(id: 1),
                message: nil
            ))
        )
        return CashTenderViewModel(totalCents: totalCents, transactionRequest: req, api: resolvedApi)
    }
}

// MARK: - PosTransactionMockAPIClient

/// Minimal mock API that stubs only `posTransaction`.
private final class PosTransactionMockAPIClient: APIClient, @unchecked Sendable {
    let result: Result<PosTransactionResponse, Error>

    init(result: Result<PosTransactionResponse, Error>) {
        self.result = result
    }

    func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func post<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T {
        if path.contains("/pos/transaction") {
            return try result.get() as! T
        }
        throw URLError(.badURL)
    }

    func put<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(
        _ path: String, body: B, as type: T.Type
    ) async throws -> T { throw URLError(.badURL) }

    func delete(_ path: String) async throws {}

    func getEnvelope<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem]?, as type: T.Type
    ) async throws -> APIResponse<T> { throw URLError(.badURL) }

    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: (any AuthSessionRefresher)?) async {}
}
#endif
