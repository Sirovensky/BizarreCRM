import Foundation

// §20.5 — Tombstone support
//
// Deleted items propagate as `deleted_at != null` in their JSON payload so
// the server (and any other device receiving via WS / silent push) drops
// the row from cache rather than re-inserting it on next sync.
//
// This file owns the canonical tombstone payload shape used everywhere a
// `delete` `SyncOp` is enqueued (`AbstractCachedRepository.delete(id:)` plus
// any domain-specific delete path that builds its own op).
//
// Wire format:
//
//   {
//     "id":         "<entity_id>",
//     "deleted":    true,
//     "deleted_at": "2026-04-29T12:34:56Z"
//   }
//
// Inbound delta-sync rows whose `deleted_at` is non-null pass through
// `Tombstone.isTombstone(payload:)` so domain code can drop them locally
// without a special-case `op == "delete"` check.

public struct Tombstone: Codable, Sendable, Equatable {
    public let id: String
    public let deleted: Bool
    public let deletedAt: Date

    public init(id: String, deletedAt: Date = .now) {
        self.id = id
        self.deleted = true
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deleted
        case deletedAt = "deleted_at"
    }

    // MARK: - Encoding

    /// Encodes a tombstone with an ISO-8601 `deleted_at` so the server (and
    /// other clients) can sort / dedupe deletes correctly.
    public func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    // MARK: - Decoding helpers

    /// Returns `true` if the given JSON payload looks like a tombstone (has
    /// `deleted_at` set to a non-null timestamp). Used by domain repositories
    /// during inbound delta-sync to drop rows from local cache.
    public static func isTombstone(payload: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: payload),
            let dict = object as? [String: Any]
        else { return false }
        if let deletedAt = dict["deleted_at"], !(deletedAt is NSNull) {
            return true
        }
        return false
    }

    /// Decodes a tombstone payload, or returns `nil` if not a tombstone.
    public static func decode(payload: Data) -> Tombstone? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Tombstone.self, from: payload)
    }
}
