import Foundation

/// Cursor-pagination envelope per §20.5. Every list endpoint returns this
/// shape (either natively or via the server-side PagedToCursorAdapter).
///
///   `{ "data": [...], "next_cursor": "...", "stream_end_at": "..." }`
///
/// `stream_end_at` is set when the server has no more rows beyond the cursor
/// — signals iOS to flip `SyncStateRecord.serverExhaustedAt` and stop
/// `loadMoreIfNeeded` from firing.
public struct CursorPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public let data: [Item]
    public let nextCursor: String?
    public let streamEndAt: Date?

    public init(data: [Item], nextCursor: String? = nil, streamEndAt: Date? = nil) {
        self.data = data
        self.nextCursor = nextCursor
        self.streamEndAt = streamEndAt
    }

    enum CodingKeys: String, CodingKey {
        case data
        case nextCursor = "next_cursor"
        case streamEndAt = "stream_end_at"
    }
}

public extension APIClient {
    /// Fetch a list page with cursor + limit. The list envelope matches
    /// `{ success, data, message }` where `data` itself is a `CursorPage<Item>`.
    ///
    /// Callers pass additional filter/query params via `extraQuery`; the
    /// cursor + limit are added here.
    func page<Item: Decodable & Sendable>(
        _ path: String,
        cursor: String? = nil,
        limit: Int = 50,
        extraQuery: [URLQueryItem] = [],
        as type: Item.Type
    ) async throws -> CursorPage<Item> {
        var query = extraQuery
        if let cursor {
            query.append(URLQueryItem(name: "cursor", value: cursor))
        }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        return try await get(path, query: query, as: CursorPage<Item>.self)
    }
}
