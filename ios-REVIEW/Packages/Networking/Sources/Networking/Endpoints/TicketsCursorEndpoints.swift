import Foundation

// MARK: - §4.1 Cursor-based pagination for Tickets
//
// Server: `GET /api/v1/tickets?cursor=<opaque>&limit=50`
// The server returns a next_cursor opaque string when more pages remain.
// iOS list reads from GRDB via ValueObservation; this endpoint upserts the
// fetched page into GRDB so subsequent reads are instant from disk.
//
// hasMore is derived from { oldestCachedAt, serverExhaustedAt? } per filter,
// NOT from total_pages (§4.1 spec).

/// One page of tickets returned by the cursor-paginated endpoint.
public struct TicketsCursorPage: Decodable, Sendable {
    public let tickets: [TicketSummary]
    /// Opaque cursor for the next page; nil when the server has no more rows.
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case tickets
        case nextCursor = "next_cursor"
    }
}

public extension APIClient {
    /// `GET /api/v1/tickets?cursor=<c>&limit=50` — cursor-paginated list.
    ///
    /// All existing filter/sort/keyword params still apply; cursor is appended.
    /// When `cursor` is nil this fetches the first page (same as the non-cursor
    /// `listTickets` call but returning `TicketsCursorPage` with cursor forwarding).
    func listTicketsCursor(
        filter: TicketListFilter = .all,
        keyword: String? = nil,
        sort: TicketSortOrder = .newest,
        cursor: String? = nil,
        limit: Int = 50
    ) async throws -> TicketsCursorPage {
        var items = filter.queryItems
        items.append(sort.queryItem)
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        if let keyword, !keyword.isEmpty {
            items.append(URLQueryItem(name: "keyword", value: keyword))
        }
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        // The server wraps the list in the standard envelope { success, data }.
        // For backwards compat, attempt cursor envelope first; fall back to the
        // existing TicketsListResponse shape when next_cursor is absent.
        do {
            return try await get("/api/v1/tickets", query: items, as: TicketsCursorPage.self)
        } catch {
            // Fallback: decode from TicketsListResponse (no cursor) — treat as last page.
            let legacy = try await get("/api/v1/tickets", query: items, as: TicketsListResponse.self)
            return TicketsCursorPage(tickets: legacy.tickets, nextCursor: nil)
        }
    }
}
