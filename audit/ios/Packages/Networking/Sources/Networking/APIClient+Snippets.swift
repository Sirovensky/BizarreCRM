import Foundation

/// Snippets-module conveniences on `APIClient`.
///
/// Ground truth routes (packages/server/src/routes/snippets.routes.ts):
///   GET    /snippets          → [Snippet]   (optional ?category=)
///   POST   /snippets          → Snippet
///   PUT    /snippets/:id      → Snippet
///   DELETE /snippets/:id      → { message: String }
///
/// Envelope: { success, data, message }
/// This extension is append-only per §12 ownership rules.
public extension APIClient {

    // MARK: - List

    /// `GET /api/v1/snippets` — returns all snippets, optionally filtered by category.
    func listSnippets(category: String? = nil) async throws -> [Snippet] {
        var query: [URLQueryItem]? = nil
        if let cat = category, !cat.isEmpty {
            query = [URLQueryItem(name: "category", value: cat)]
        }
        return try await get("/api/v1/snippets", query: query, as: [Snippet].self)
    }

    // MARK: - Create

    /// `POST /api/v1/snippets` — create a new snippet.
    func createSnippet(_ request: CreateSnippetRequest) async throws -> Snippet {
        return try await post("/api/v1/snippets", body: request, as: Snippet.self)
    }

    // MARK: - Update

    /// `PUT /api/v1/snippets/:id` — update an existing snippet.
    func updateSnippet(id: Int64, _ request: UpdateSnippetRequest) async throws -> Snippet {
        return try await put("/api/v1/snippets/\(id)", body: request, as: Snippet.self)
    }

    // MARK: - Delete

    /// `DELETE /api/v1/snippets/:id` — delete a snippet.
    func deleteSnippet(id: Int64) async throws {
        try await delete("/api/v1/snippets/\(id)")
    }
}

// MARK: - DTO: Snippet

/// Server row: `id`, `shortcode`, `title`, `content`, `category`, `created_by`, `created_at`, `updated_at`.
public struct Snippet: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int64
    public let shortcode: String
    public let title: String
    public let content: String
    public let category: String?
    public let createdBy: Int64?
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        id: Int64,
        shortcode: String,
        title: String,
        content: String,
        category: String? = nil,
        createdBy: Int64? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.id = id
        self.shortcode = shortcode
        self.title = title
        self.content = content
        self.category = category
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, shortcode, title, content, category
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - DTO: CreateSnippetRequest

/// `POST /api/v1/snippets` body.
/// Server requires: shortcode (<=50, [a-zA-Z0-9_-]), title (<=200), content (<=10000).
public struct CreateSnippetRequest: Encodable, Sendable {
    public let shortcode: String
    public let title: String
    public let content: String
    public let category: String?

    public init(shortcode: String, title: String, content: String, category: String? = nil) {
        self.shortcode = shortcode
        self.title = title
        self.content = content
        self.category = category
    }
}

// MARK: - DTO: UpdateSnippetRequest

/// `PUT /api/v1/snippets/:id` body. All fields optional (server merges with existing).
public struct UpdateSnippetRequest: Encodable, Sendable {
    public let shortcode: String?
    public let title: String?
    public let content: String?
    public let category: String?

    public init(
        shortcode: String? = nil,
        title: String? = nil,
        content: String? = nil,
        category: String? = nil
    ) {
        self.shortcode = shortcode
        self.title = title
        self.content = content
        self.category = category
    }
}
