import Foundation
import Core
import Networking
import Persistence

// MARK: - §9.4 Lead offline create queue

/// Mirrors CustomerOfflineQueue for the Leads domain.
/// Serializes `CreateLeadRequest` into the `sync_queue` when the device is offline.
public enum LeadOfflineQueue {

    /// True if the error is a connectivity error (enqueue), not a server 4xx/5xx (surface).
    public static func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
                 .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
                return true
            default: return false
            }
        }
        if let transport = error as? APITransportError {
            switch transport {
            case .networkUnavailable, .noBaseURL: return true
            case .httpStatus(let code, _): return code == 0
            default: return false
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return true
            default: return false
            }
        }
        return false
    }

    public static func encode<B: Encodable>(_ body: B) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodeError.notUTF8
        }
        return json
    }

    public enum EncodeError: Error { case notUTF8 }

    /// Enqueue a pending lead mutation into the shared sync queue.
    public static func enqueue(
        op: String,
        entityServerId: Int64? = nil,
        payload: String
    ) async {
        let record = SyncQueueRecord(
            op: op,
            entity: "lead",
            entityLocalId: nil,
            entityServerId: entityServerId.map(String.init),
            payload: payload
        )
        do {
            try await SyncQueueStore.shared.enqueue(record)
            AppLog.sync.info("Queued offline lead \(op, privacy: .public)")
        } catch {
            AppLog.sync.error("Failed to enqueue lead \(op, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Sentinel for pending sync IDs

/// Negative sentinel ID used in the UI while the lead awaits server confirmation.
public let PendingSyncLeadId: Int64 = -1
