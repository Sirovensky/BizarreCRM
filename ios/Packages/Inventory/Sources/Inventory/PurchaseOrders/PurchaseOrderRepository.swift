import Foundation
import Networking
import Core

// MARK: - PurchaseOrderRepository

public protocol PurchaseOrderRepository: Sendable {
    func list(status: String?) async throws -> [PurchaseOrder]
    func get(id: Int64) async throws -> PurchaseOrder
    func create(_ body: CreatePurchaseOrderRequest) async throws -> PurchaseOrder
    func update(id: Int64, _ body: UpdatePurchaseOrderRequest) async throws -> PurchaseOrder
    /// Transition a draft PO to pending (approve).
    func approve(id: Int64) async throws -> PurchaseOrder
    /// Transition a PO to cancelled status.
    func cancel(id: Int64, reason: String?) async throws -> PurchaseOrder
    func receive(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder
    /// Email PO to the supplier. Server transitions status to "ordered".
    func send(id: Int64) async throws -> PurchaseOrder
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

    public func approve(id: Int64) async throws -> PurchaseOrder {
        try await api.approvePurchaseOrder(id: id)
    }

    public func cancel(id: Int64, reason: String? = nil) async throws -> PurchaseOrder {
        try await api.cancelPurchaseOrder(id: id, reason: reason)
    }

    public func receive(id: Int64, _ body: ReceivePORequest) async throws -> PurchaseOrder {
        try await api.receivePurchaseOrder(id: id, body)
    }

    public func send(id: Int64) async throws -> PurchaseOrder {
        try await api.sendPurchaseOrder(id: id)
    }
}
