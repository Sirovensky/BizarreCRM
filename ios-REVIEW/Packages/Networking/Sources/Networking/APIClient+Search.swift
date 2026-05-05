import Foundation

// MARK: - Search notes endpoint
//
// Server route: packages/server/src/routes/search.routes.ts — GET /notes
// Envelope: { success, data: { notes: [...], pagination: {...} } }

/// One note row returned by `GET /api/v1/search/notes`.
public struct SearchNoteRow: Decodable, Sendable, Identifiable {
    public let id: Int64
    public let ticketId: Int64?
    public let type: String?
    public let content: String?
    public let createdAt: String?
    public let orderId: String?
    public let deviceName: String?
    public let authorFirst: String?
    public let authorLast: String?
    public let customerFirst: String?
    public let customerLast: String?

    public var authorName: String {
        [authorFirst, authorLast].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
    }

    public var customerName: String {
        [customerFirst, customerLast].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " ")
    }
}

public struct SearchNotesResponse: Decodable, Sendable {
    public let notes: [SearchNoteRow]
    public let pagination: Pagination?

    public struct Pagination: Decodable, Sendable {
        public let page: Int?
        public let perPage: Int?
        public let total: Int?
        public let totalPages: Int?

        enum CodingKeys: String, CodingKey {
            case page, total
            case perPage = "per_page"
            case totalPages = "total_pages"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notes = (try? c.decode([SearchNoteRow].self, forKey: .notes)) ?? []
        pagination = try? c.decode(Pagination.self, forKey: .pagination)
    }

    enum CodingKeys: String, CodingKey { case notes, pagination }
}

public extension APIClient {

    /// `GET /api/v1/search/notes?q=term&type=internal&page=1&pagesize=20`
    ///
    /// Knowledge-base search across all ticket notes visible to the current user.
    /// Respects the same ticket-assignment visibility gate as the server route.
    ///
    /// - Parameters:
    ///   - query:    Search term (minimum 2 characters server-side).
    ///   - type:     Optional note type filter: `"internal"`, `"diagnostic"`, `"email"`.
    ///   - page:     1-based page number (default 1).
    ///   - pageSize: Results per page (default 20, max 100).
    func searchNotes(
        query: String,
        type: String? = nil,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> SearchNotesResponse {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pagesize", value: String(pageSize)),
        ]
        if let type, !type.isEmpty {
            items.append(URLQueryItem(name: "type", value: type))
        }
        return try await get("/api/v1/search/notes", query: items, as: SearchNotesResponse.self)
    }
}
