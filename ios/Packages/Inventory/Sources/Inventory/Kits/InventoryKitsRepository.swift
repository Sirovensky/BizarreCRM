import Foundation
import Networking

// MARK: - InventoryKitsRepository
//
// Wraps the live server endpoints:
//   GET    /api/v1/inventory/kits        — list
//   GET    /api/v1/inventory/kits/:id    — detail
//   POST   /api/v1/inventory/kits        — create  (inventory.create permission)
//   DELETE /api/v1/inventory/kits/:id    — delete  (inventory.delete permission)

// MARK: Protocol

public protocol InventoryKitsRepository: Sendable {
    func listKits() async throws -> [InventoryKit]
    func getKit(id: Int64) async throws -> InventoryKit
    func deleteKit(id: Int64) async throws
}

// MARK: Live implementation

public actor InventoryKitsRepositoryImpl: InventoryKitsRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    /// GET /api/v1/inventory/kits
    public func listKits() async throws -> [InventoryKit] {
        try await api.listInventoryKits()
    }

    /// GET /api/v1/inventory/kits/:id
    public func getKit(id: Int64) async throws -> InventoryKit {
        try await api.getInventoryKit(id: id)
    }

    /// DELETE /api/v1/inventory/kits/:id
    public func deleteKit(id: Int64) async throws {
        try await api.deleteInventoryKit(id: id)
    }
}

// MARK: - APIClient extension

public extension APIClient {

    /// GET /api/v1/inventory/kits
    func listInventoryKits() async throws -> [InventoryKit] {
        try await get("/api/v1/inventory/kits", query: nil, as: [InventoryKit].self)
    }

    /// GET /api/v1/inventory/kits/:id
    func getInventoryKit(id: Int64) async throws -> InventoryKit {
        try await get("/api/v1/inventory/kits/\(id)", query: nil, as: InventoryKit.self)
    }

    /// POST /api/v1/inventory/kits
    func createInventoryKit(_ body: CreateInventoryKitRequest) async throws -> InventoryKit {
        try await post("/api/v1/inventory/kits", body: body, as: InventoryKit.self)
    }

    /// DELETE /api/v1/inventory/kits/:id
    func deleteInventoryKit(id: Int64) async throws {
        try await delete("/api/v1/inventory/kits/\(id)")
    }
}

// MARK: - Request bodies

public struct CreateInventoryKitRequest: Encodable, Sendable {
    public let name: String
    public let description: String?
    public let items: [KitItemRequest]

    public init(name: String, description: String? = nil, items: [KitItemRequest]) {
        self.name = name
        self.description = description
        self.items = items
    }
}

public struct KitItemRequest: Encodable, Sendable {
    public let inventoryItemId: Int64
    public let quantity: Int

    public init(inventoryItemId: Int64, quantity: Int) {
        self.inventoryItemId = inventoryItemId
        self.quantity = quantity
    }

    enum CodingKeys: String, CodingKey {
        case inventoryItemId = "inventory_item_id"
        case quantity
    }
}
