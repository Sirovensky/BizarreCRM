import Foundation
import Core
import Networking
import Persistence

/// Shared plumbing for Create/Edit view-models: detect network-class errors,
/// serialize the request body into the `sync_queue` so the drainer can pick
/// it up later. §20.2 — every mutation must land either on the server or in
/// the queue.
///
/// Mirrors `CustomerOfflineQueue` — same classification logic, same snake-
/// case-aware encoder. Only the `entity` string differs.
enum InventoryOfflineQueue {

    /// `true` if the error represents "couldn't reach the server" rather than
    /// a 4xx/5xx response with a useful server message. On network errors we
    /// enqueue; on server errors we surface the message.
    static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .networkConnectionLost,
                 .timedOut,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed,
                 .internationalRoamingOff,
                 .dataNotAllowed,
                 .secureConnectionFailed:
                return true
            default:
                return false
            }
        }
        if let transport = error as? APITransportError {
            switch transport {
            case .networkUnavailable, .noBaseURL:
                return true
            case .httpStatus(let code, _):
                // Code 0 is our local marker for "could not establish connection".
                // Anything else is a real server response — not a network error.
                return code == 0
            default:
                return false
            }
        }
        // NSError bridging — sometimes URLError surfaces as NSURLErrorDomain.
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// JSON-encode `body` using the same snake_case-aware encoder the main
    /// APIClient uses (the Encodable types declare explicit CodingKeys so the
    /// default encoder is all we need).
    static func encode<B: Encodable>(_ body: B) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodeError.notUTF8
        }
        return json
    }

    enum EncodeError: Error { case notUTF8 }

    /// Enqueue a pending mutation. `entityServerId` is only set on updates —
    /// creates have no server id yet, only a negative "pending" id used by
    /// the UI.
    static func enqueue(
        op: String,
        entityServerId: Int64? = nil,
        payload: String
    ) async {
        let record = SyncQueueRecord(
            op: op,
            entity: "inventory",
            entityLocalId: nil,
            entityServerId: entityServerId.map(String.init),
            payload: payload
        )
        do {
            try await SyncQueueStore.shared.enqueue(record)
            AppLog.sync.info("Queued offline inventory \(op, privacy: .public)")
        } catch {
            AppLog.sync.error("Failed to enqueue inventory \(op, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
