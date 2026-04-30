import Foundation
import Networking

public protocol InventoryRepository: Sendable {
    func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem]
    func listAdvanced(
        filter: InventoryFilter,
        sort: InventorySortOption,
        advanced: InventoryAdvancedFilter,
        keyword: String?
    ) async throws -> [InventoryListItem]
}

public actor InventoryRepositoryImpl: InventoryRepository {
    private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func list(filter: InventoryFilter, keyword: String?) async throws -> [InventoryListItem] {
        try await api.listInventory(filter: filter, keyword: keyword).items
    }

    public func listAdvanced(
        filter: InventoryFilter,
        sort: InventorySortOption,
        advanced: InventoryAdvancedFilter,
        keyword: String?
    ) async throws -> [InventoryListItem] {
        try await api.listInventoryAdvanced(
            filter: filter,
            sort: sort,
            advanced: advanced,
            keyword: keyword
        ).items
    }
}
