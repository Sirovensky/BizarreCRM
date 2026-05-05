import Foundation
@testable import Inventory

// MARK: - MockPurchaseOrderRepository

/// Controllable test double for PurchaseOrderRepository.
/// Inject canned results per method; calls are recorded for assertion.
final class MockPurchaseOrderRepository: PurchaseOrderRepository, @unchecked Sendable {

    // MARK: Canned results

    var listResult: Result<[PurchaseOrder], Error> = .success([])
    var getResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.draft)
    var createResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.draft)
    var updateResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.draft)
    var approveResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.pending)
    var cancelResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.cancelled)
    var receiveResult: Result<PurchaseOrder, Error> = .success(MockPOFixtures.partial)

    // MARK: Call tracking

    private(set) var listCallCount: Int = 0
    private(set) var listLastStatus: String?
    private(set) var getCallCount: Int = 0
    private(set) var getLastId: Int64?
    private(set) var createCallCount: Int = 0
    private(set) var updateCallCount: Int = 0
    private(set) var approveCallCount: Int = 0
    private(set) var approveLastId: Int64?
    private(set) var cancelCallCount: Int = 0
    private(set) var cancelLastId: Int64?
    private(set) var cancelLastReason: String?
    private(set) var receiveCallCount: Int = 0

    // MARK: PurchaseOrderRepository

    func list(status: String?) async throws -> [PurchaseOrder] {
        listCallCount += 1
        listLastStatus = status
        return try listResult.get()
    }

    func get(id: Int64) async throws -> PurchaseOrder {
        getCallCount += 1
        getLastId = id
        return try getResult.get()
    }

    func create(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder {
        createCallCount += 1
        return try createResult.get()
    }

    func update(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder {
        updateCallCount += 1
        return try updateResult.get()
    }

    func approve(id: Int64) async throws -> PurchaseOrder {
        approveCallCount += 1
        approveLastId = id
        return try approveResult.get()
    }

    func cancel(id: Int64, reason: String?) async throws -> PurchaseOrder {
        cancelCallCount += 1
        cancelLastId = id
        cancelLastReason = reason
        return try cancelResult.get()
    }

    func receive(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder {
        receiveCallCount += 1
        return try receiveResult.get()
    }
}

// MARK: - MockSupplierRepository

final class MockSupplierRepository: SupplierRepository, @unchecked Sendable {

    var listResult: Result<[Supplier], Error> = .success([MockPOFixtures.supplier])
    var getResult: Result<Supplier, Error> = .success(MockPOFixtures.supplier)

    private(set) var listCallCount: Int = 0
    private(set) var getCallCount: Int = 0

    func list() async throws -> [Supplier] {
        listCallCount += 1
        return try listResult.get()
    }

    func get(id: Int64) async throws -> Supplier {
        getCallCount += 1
        return try getResult.get()
    }

    func create(_ body: SupplierRequest) async throws -> Supplier { try getResult.get() }
    func update(id: Int64, _ body: SupplierRequest) async throws -> Supplier { try getResult.get() }
    func delete(id: Int64) async throws {}
}

// MARK: - MockPOFixtures

enum MockPOFixtures {

    static let supplier = Supplier(
        id: 1,
        name: "Acme Corp",
        contactName: "Bob",
        email: "bob@acme.com",
        phone: "555-1234",
        address: "1 Main St",
        paymentTerms: "Net 30",
        leadTimeDays: 7
    )

    static let line = POLineItem(
        id: 10,
        sku: "WIDGET-001",
        name: "Widget",
        qtyOrdered: 5,
        qtyReceived: 0,
        unitCostCents: 1000,
        lineTotalCents: 5000
    )

    static let draft = PurchaseOrder(
        id: 100,
        supplierId: 1,
        status: .draft,
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        items: [line],
        totalCents: 5000
    )

    static let pending = PurchaseOrder(
        id: 100,
        supplierId: 1,
        status: .pending,
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        items: [line],
        totalCents: 5000
    )

    static let partial = PurchaseOrder(
        id: 100,
        supplierId: 1,
        status: .partial,
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        items: [line],
        totalCents: 5000
    )

    static let cancelled = PurchaseOrder(
        id: 100,
        supplierId: 1,
        status: .cancelled,
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        items: [line],
        totalCents: 5000
    )

    static let received = PurchaseOrder(
        id: 100,
        supplierId: 1,
        status: .received,
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        items: [
            POLineItem(id: 10, sku: "WIDGET-001", name: "Widget",
                       qtyOrdered: 5, qtyReceived: 5,
                       unitCostCents: 1000, lineTotalCents: 5000)
        ],
        totalCents: 5000
    )
}

// MARK: - Helpers

enum MockError: Error { case generic }
