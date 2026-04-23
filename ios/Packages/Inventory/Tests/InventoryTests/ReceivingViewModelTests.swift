import XCTest
@testable import Inventory
import Networking

@MainActor
final class ReceivingDetailViewModelTests: XCTestCase {

    // MARK: - applyBarcode

    func test_applyBarcode_matchingSku_incrementsQty() {
        let api = ReceivingStubAPIClient(order: .init(
            id: 1, status: "open",
            lineItems: [.init(id: 10, sku: "WDG-1", orderedQty: 5, receivedQty: 0)]
        ))
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        // Manually pre-load order
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))

        let found = vm.applyBarcode("WDG-1")
        XCTAssertTrue(found)
        XCTAssertEqual(vm.receivedQty[10], "1")

        let found2 = vm.applyBarcode("WDG-1")
        XCTAssertTrue(found2)
        XCTAssertEqual(vm.receivedQty[10], "2")
    }

    func test_applyBarcode_unknownSku_returnsFalse() {
        let api = ReceivingStubAPIClient(order: .init(
            id: 1, status: "open",
            lineItems: [.init(id: 10, sku: "WDG-1", orderedQty: 5, receivedQty: 0)]
        ))
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))

        let qtyBefore = vm.receivedQty[10]   // pre-seeded by _setOrderForTesting
        let found = vm.applyBarcode("DOES-NOT-EXIST")
        XCTAssertFalse(found)
        // Unknown SKU should NOT change any existing qty
        XCTAssertEqual(vm.receivedQty[10], qtyBefore)
    }

    func test_applyBarcode_noOrder_returnsFalse() {
        let api = ReceivingStubAPIClient(order: nil)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        let found = vm.applyBarcode("WDG-1")
        XCTAssertFalse(found)
    }

    // MARK: - hasOverReceipt

    func test_hasOverReceipt_false_whenWithinOrdered() {
        let api = ReceivingStubAPIClient(order: nil)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))
        vm.receivedQty[10] = "5"
        XCTAssertFalse(vm.hasOverReceipt)
    }

    func test_hasOverReceipt_true_whenExceedsOrdered() {
        let api = ReceivingStubAPIClient(order: nil)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))
        vm.receivedQty[10] = "9"
        XCTAssertTrue(vm.hasOverReceipt)
    }

    // MARK: - ReconciliationEntry

    func test_reconciliationEntry_deltas() {
        let exact = ReconciliationEntry(sku: "A", name: "A", orderedQty: 5, receivedQty: 5)
        XCTAssertEqual(exact.delta, 0)
        XCTAssertTrue(exact.isExact)
        XCTAssertFalse(exact.isOver)
        XCTAssertFalse(exact.isUnder)

        let over = ReconciliationEntry(sku: "B", name: "B", orderedQty: 3, receivedQty: 5)
        XCTAssertEqual(over.delta, 2)
        XCTAssertTrue(over.isOver)
        XCTAssertFalse(over.isUnder)

        let under = ReconciliationEntry(sku: "C", name: "C", orderedQty: 10, receivedQty: 7)
        XCTAssertEqual(under.delta, -3)
        XCTAssertTrue(under.isUnder)
        XCTAssertFalse(under.isOver)
    }

    // MARK: - Helpers

    private func makeOrder(sku: String, orderedQty: Int, receivedQty: Int) -> ReceivingOrder {
        ReceivingOrder(
            id: 1, status: "open",
            lineItems: [ReceivingLineItem(id: 10, sku: sku,
                                          orderedQty: orderedQty, receivedQty: receivedQty)]
        )
    }
}

// MARK: - finalize delta logic tests

@MainActor
final class ReceivingFinalizeTests: XCTestCase {

    func test_finalize_nothingEntered_setsErrorMessage() async {
        let api = ReceivingStubAPIClient(order: nil)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        // Load order with receivedQty already = orderedQty (nothing new to receive)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 5))
        vm.receivedQty[10] = "5"   // same as already received → delta = 0
        await vm.finalize()
        XCTAssertEqual(vm.errorMessage, "No quantities entered to receive.")
        XCTAssertFalse(vm.showReconciliation)
    }

    func test_finalize_success_setsShowReconciliation() async {
        let api = ReceivingStubAPIClient(order: .init(
            id: 1, status: "open",
            lineItems: [.init(id: 10, sku: "WDG-1", orderedQty: 5, receivedQty: 0)]
        ))
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))
        vm.receivedQty[10] = "3"   // receive 3 new (delta = 3)
        await vm.finalize()
        XCTAssertTrue(vm.showReconciliation)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.finalizeResult.count, 1)
        XCTAssertEqual(vm.finalizeResult[0].receivedQty, 3)
    }

    func test_finalize_sendsOnlyDeltaLines() async {
        let api = ReceivingStubAPIClient(order: nil)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        let order = ReceivingOrder(
            id: 1, status: "open",
            lineItems: [
                ReceivingLineItem(id: 10, sku: "A", orderedQty: 5, receivedQty: 3),
                ReceivingLineItem(id: 11, sku: "B", orderedQty: 4, receivedQty: 4)  // fully received
            ]
        )
        vm._setOrderForTesting(order)
        vm.receivedQty[10] = "5"   // A: new delta = 2
        vm.receivedQty[11] = "4"   // B: no delta
        await vm.finalize()
        XCTAssertTrue(vm.showReconciliation)
        XCTAssertEqual(vm.finalizeResult.count, 2)
        // Line A reconciliation shows total qty received = 5
        XCTAssertEqual(vm.finalizeResult.first(where: { $0.sku == "A" })?.receivedQty, 5)
    }

    func test_finalize_offline_showsReconciliationOptimistically() async {
        let api = ReceivingStubAPIClient(order: nil, simulateNetworkError: true)
        let vm = ReceivingDetailViewModel(api: api, orderId: 1)
        vm.applyOrder(makeOrder(sku: "WDG-1", orderedQty: 5, receivedQty: 0))
        vm.receivedQty[10] = "2"
        await vm.finalize()
        XCTAssertTrue(vm.showReconciliation)
        XCTAssertNil(vm.errorMessage)
    }

    // MARK: - Helpers

    private func makeOrder(sku: String, orderedQty: Int, receivedQty: Int) -> ReceivingOrder {
        ReceivingOrder(
            id: 1, status: "open",
            lineItems: [ReceivingLineItem(id: 10, sku: sku,
                                          orderedQty: orderedQty, receivedQty: receivedQty)]
        )
    }
}

// MARK: - Stub client

actor ReceivingStubAPIClient: APIClient {
    let stubbedOrder: ReceivingOrder?
    let simulateNetworkError: Bool

    init(order: ReceivingOrder?, simulateNetworkError: Bool = false) {
        self.stubbedOrder = order
        self.simulateNetworkError = simulateNetworkError
    }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        if simulateNetworkError { throw URLError(.notConnectedToInternet) }
        // Finalize endpoint
        if let r = CreatedResource(id: 99) as? T { return r }
        throw APITransportError.noBaseURL
    }
    func put<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func patch<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func delete(_ path: String) async throws {}
    func getEnvelope<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> APIResponse<T> {
        throw APITransportError.noBaseURL
    }
    func setAuthToken(_ token: String?) async {}
    func setBaseURL(_ url: URL?) async {}
    func currentBaseURL() async -> URL? { nil }
    func setRefresher(_ refresher: AuthSessionRefresher?) async {}
}

// Helper: expose a test-only setter so we can pre-load the order without
// triggering a network call in unit tests.
extension ReceivingDetailViewModel {
    func applyOrder(_ order: ReceivingOrder) {
        _setOrderForTesting(order)
    }
}
