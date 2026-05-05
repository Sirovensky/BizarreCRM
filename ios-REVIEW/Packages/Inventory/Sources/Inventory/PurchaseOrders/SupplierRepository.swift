import Foundation
import Networking
import Core

// MARK: - SupplierRepository

public protocol SupplierRepository: Sendable {
    func list() async throws -> [Supplier]
    func get(id: Int64) async throws -> Supplier
    func create(_ body: SupplierRequest) async throws -> Supplier
    func update(id: Int64, _ body: SupplierRequest) async throws -> Supplier
    func delete(id: Int64) async throws
}

// MARK: - LiveSupplierRepository

public actor LiveSupplierRepository: SupplierRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func list() async throws -> [Supplier] {
        try await api.listSuppliers()
    }

    public func get(id: Int64) async throws -> Supplier {
        try await api.getSupplier(id: id)
    }

    public func create(_ body: SupplierRequest) async throws -> Supplier {
        try await api.createSupplier(body)
    }

    public func update(id: Int64, _ body: SupplierRequest) async throws -> Supplier {
        try await api.updateSupplier(id: id, body)
    }

    public func delete(id: Int64) async throws {
        try await api.deleteSupplier(id: id)
    }
}
