import Foundation
import Observation
import Core
import Networking

@MainActor
@Observable
public final class InventoryDetailViewModel {
    public enum State: Sendable {
        case loading
        case loaded(InventoryDetailResponse)
        case failed(String)
    }

    public var state: State = .loading
    public let itemId: Int64

    @ObservationIgnored private let repo: InventoryDetailRepository

    public init(repo: InventoryDetailRepository, itemId: Int64) {
        self.repo = repo
        self.itemId = itemId
    }

    public func load() async {
        if case .loaded = state { /* soft */ } else { state = .loading }
        do {
            state = .loaded(try await repo.detail(id: itemId))
        } catch {
            AppLog.ui.error("Inventory detail load failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
        }
    }
}

public protocol InventoryDetailRepository: Sendable {
    func detail(id: Int64) async throws -> InventoryDetailResponse
}

public actor InventoryDetailRepositoryImpl: InventoryDetailRepository {
    private let api: APIClient
    public init(api: APIClient) { self.api = api }
    public func detail(id: Int64) async throws -> InventoryDetailResponse {
        try await api.inventoryItem(id: id)
    }
}
