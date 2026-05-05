import Foundation
import Core
import Networking
import Persistence

/// §20.3 — replay handlers for queued inventory mutations. Mirrors
/// `CustomerSyncHandlers`. Registered with `SyncFlusher.shared` at app
/// launch.
public enum InventorySyncHandlers {

    public static func register(api: APIClient) async {
        await SyncFlusher.shared.register(entity: "inventory", op: "create") { record in
            try await handleCreate(record, api: api)
        }
        await SyncFlusher.shared.register(entity: "inventory", op: "update") { record in
            try await handleUpdate(record, api: api)
        }
    }

    private static func handleCreate(_ record: SyncQueueRecord, api: APIClient) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = record.payload.data(using: .utf8) else {
            throw SyncReplayError.payloadEncoding
        }
        let req = try decoder.decode(CreateInventoryItemRequest.self, from: data)
        _ = try await api.createInventoryItem(req)
    }

    private static func handleUpdate(_ record: SyncQueueRecord, api: APIClient) async throws {
        guard let idString = record.entityServerId, let id = Int64(idString) else {
            throw SyncReplayError.missingServerId
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = record.payload.data(using: .utf8) else {
            throw SyncReplayError.payloadEncoding
        }
        let req = try decoder.decode(UpdateInventoryItemRequest.self, from: data)
        _ = try await api.updateInventoryItem(id: id, req)
    }

    public enum SyncReplayError: Error, LocalizedError {
        case payloadEncoding
        case missingServerId

        public var errorDescription: String? {
            switch self {
            case .payloadEncoding: return "Queued inventory payload is not valid UTF-8 JSON"
            case .missingServerId: return "Inventory update row is missing entity_server_id"
            }
        }
    }
}
