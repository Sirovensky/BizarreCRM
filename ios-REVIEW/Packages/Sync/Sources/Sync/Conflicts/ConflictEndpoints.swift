import Foundation
import Networking

// Ground truth: packages/server/src/routes/syncConflicts.routes.ts
//   GET  /api/v1/sync/conflicts             — list (manager+, paginated)
//   GET  /api/v1/sync/conflicts/:id         — detail (manager+)
//   POST /api/v1/sync/conflicts/:id/resolve — resolve (manager+)
//
// Envelope: { success: Bool, data: T?, message: String? }

// MARK: - APIClient + Conflict endpoints

public extension APIClient {

    // MARK: List

    /// `GET /api/v1/sync/conflicts`
    /// - Parameters:
    ///   - status: Optional filter by `ConflictStatus` raw value.
    ///   - entityKind: Optional filter by entity kind string.
    ///   - page: 1-based page number.
    ///   - pageSize: Results per page (server default 25).
    func listConflicts(
        status: ConflictStatus? = nil,
        entityKind: String? = nil,
        page: Int = 1,
        pageSize: Int = 25
    ) async throws -> ConflictListEnvelope {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pagesize", value: "\(pageSize)"),
        ]
        if let status {
            query.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        if let entityKind, !entityKind.isEmpty {
            query.append(URLQueryItem(name: "entity_kind", value: entityKind))
        }
        return try await get(
            "/api/v1/sync/conflicts",
            query: query,
            as: ConflictListEnvelope.self
        )
    }

    // MARK: Detail

    /// `GET /api/v1/sync/conflicts/:id`
    func conflictDetail(id: Int) async throws -> ConflictItem {
        try await get(
            "/api/v1/sync/conflicts/\(id)",
            as: ConflictItem.self
        )
    }

    // MARK: Resolve

    /// `POST /api/v1/sync/conflicts/:id/resolve`
    /// - Parameters:
    ///   - id: Conflict record ID.
    ///   - resolution: The chosen resolution strategy.
    ///   - notes: Optional free-text notes (≤2000 chars, server-validated).
    func resolveConflict(
        id: Int,
        resolution: Resolution,
        notes: String? = nil
    ) async throws -> ResolveConflictResult {
        let body = ResolveConflictRequest(resolution: resolution, notes: notes)
        return try await post(
            "/api/v1/sync/conflicts/\(id)/resolve",
            body: body,
            as: ResolveConflictResult.self
        )
    }
}

// MARK: - ConflictListEnvelope

/// Top-level decoded shape from `GET /api/v1/sync/conflicts`.
///
/// The server returns:
/// ```json
/// { "success": true,
///   "data": [...],
///   "meta": { "total": N, "page": N, "pageSize": N, "pages": N }
/// }
/// ```
/// `APIClient.get(_:query:as:)` unwraps the `data` field.  The list endpoint
/// returns the array directly under `data`, so we decode the outer response
/// through a wrapper that respects the envelope's `data` key.
///
/// Because `APIClient.get` calls `unwrap` on `envelope.data`, we need a type
/// that decodes from the *full* response shape. We model it as a struct that
/// contains both the rows and meta so callers can page.
public struct ConflictListEnvelope: Decodable, Sendable {
    public let rows: [ConflictItem]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let pages: Int

    // The server returns:
    //   { success, data: [...rows...], meta: { total, page, pageSize, pages } }
    //
    // APIClient.get<T>(as:) decodes the *data* field only (via APIResponse<T>).
    // To carry pagination we need to decode the whole response. We use a custom
    // init that reads from the top-level container so both data and meta arrive.
    public init(from decoder: Decoder) throws {
        // If this decoder sees only the array (i.e. APIClient unwrapped data),
        // try decoding as a plain array first.
        if var arr = try? decoder.unkeyedContainer() {
            var items: [ConflictItem] = []
            while !arr.isAtEnd {
                items.append(try arr.decode(ConflictItem.self))
            }
            self.rows = items
            self.total = items.count
            self.page = 1
            self.pageSize = items.count
            self.pages = 1
            return
        }
        // Otherwise decode from a keyed container (raw server envelope).
        enum TopKeys: String, CodingKey { case data, meta }
        enum MetaKeys: String, CodingKey { case total, page, pageSize, pages }
        let top = try decoder.container(keyedBy: TopKeys.self)
        rows = (try? top.decode([ConflictItem].self, forKey: .data)) ?? []
        if let meta = try? top.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta) {
            total    = (try? meta.decode(Int.self, forKey: .total))    ?? rows.count
            page     = (try? meta.decode(Int.self, forKey: .page))     ?? 1
            pageSize = (try? meta.decode(Int.self, forKey: .pageSize)) ?? rows.count
            pages    = (try? meta.decode(Int.self, forKey: .pages))    ?? 1
        } else {
            total = rows.count; page = 1; pageSize = rows.count; pages = 1
        }
    }
}
