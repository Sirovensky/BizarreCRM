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

// MARK: - Stub client

actor ReceivingStubAPIClient: APIClient {
    let stubbedOrder: ReceivingOrder?

    init(order: ReceivingOrder?) { self.stubbedOrder = order }

    func get<T: Decodable & Sendable>(_ path: String, query: [URLQueryItem]?, as type: T.Type) async throws -> T {
        throw APITransportError.noBaseURL
    }
    func post<T: Decodable & Sendable, B: Encodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T {
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
