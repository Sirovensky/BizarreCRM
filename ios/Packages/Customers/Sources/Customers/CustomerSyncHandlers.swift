import Foundation
import Core
import Networking
import Persistence

/// §20.3 — replay handlers for queued customer mutations. Registered with
/// `SyncFlusher.shared` at app launch by `AppServices`. Exposed as static
/// methods rather than an actor instance because they carry no state and
/// are expected to be registered exactly once.
public enum CustomerSyncHandlers {

    /// Register both create + update handlers against the shared flusher.
    /// Caller should invoke this from app startup so replay is available as
    /// soon as reachability flips online.
    public static func register(api: APIClient) async {
        await SyncFlusher.shared.register(entity: "customer", op: "create") { record in
            try await handleCreate(record, api: api)
        }
        await SyncFlusher.shared.register(entity: "customer", op: "update") { record in
            try await handleUpdate(record, api: api)
        }
    }

    private static func handleCreate(_ record: SyncQueueRecord, api: APIClient) async throws {
        // Payload was encoded with `JSONEncoder(.iso8601)` at enqueue time
        // — decode with the same strategy so dates round-trip.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = record.payload.data(using: .utf8) else {
            throw SyncReplayError.payloadEncoding
        }
        let req = try decoder.decode(CreateCustomerRequest.self, from: data)
        _ = try await api.createCustomer(req)
    }

    private static func handleUpdate(_ record: SyncQueueRecord, api: APIClient) async throws {
        guard let idString = record.entityServerId, let id = Int64(idString) else {
            // No server id → can't target a row; dead-letter it. The handler
            // flusher will escalate via markFailed → maxAttempts.
            throw SyncReplayError.missingServerId
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = record.payload.data(using: .utf8) else {
            throw SyncReplayError.payloadEncoding
        }
        let req = try decoder.decode(UpdateCustomerRequest.self, from: data)
        _ = try await api.updateCustomer(id: id, req)
    }

    public enum SyncReplayError: Error, LocalizedError {
        case payloadEncoding
        case missingServerId

        public var errorDescription: String? {
            switch self {
            case .payloadEncoding:  return "Queued payload is not valid UTF-8 JSON"
            case .missingServerId:  return "Update row is missing entity_server_id"
            }
        }
    }
}
