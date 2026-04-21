import Foundation
import Networking
import Core

// MARK: - PurchaseOrderRepository

public protocol PurchaseOrderRepository: Sendable {
    func list(status: String?) async throws -> [PurchaseOrder]
    func get(id: Int64) async throws -> PurchaseOrder
    func create(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder
    func update(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder
    func receive(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder
    func cancel(id: Int64) async throws
}

// MARK: - LivePurchaseOrderRepository

public actor LivePurchaseOrderRepository: PurchaseOrderRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func list(status: String? = nil) async throws -> [PurchaseOrder] {
        try await api.listPurchaseOrders(status: status)
    }

    public func get(id: Int64) async throws -> PurchaseOrder {
        try await api.getPurchaseOrder(id: id)
    }

    public func create(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await api.createPurchaseOrder(body)
    }

    public func update(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder {
        try await api.updatePurchaseOrder(id: id, body)
    }

    public func receive(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder {
        try await api.receivePurchaseOrder(id: id, body)
    }

    public func cancel(id: Int64) async throws {
        try await api.cancelPurchaseOrder(id: id)
    }
}
