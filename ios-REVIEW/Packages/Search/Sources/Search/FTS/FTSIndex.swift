import Foundation
import GRDB
import Core

/// §18.3 — Low-level FTS5 helper that owns the `search_index` virtual table.
///
/// Wraps a GRDB `DatabaseWriter` (thread-safe internally) so mutations and
/// reads are dispatched via the GRDB writer queue.
/// `FTSIndexStore` (an actor) is the public façade — prefer that over this type.
struct FTSIndex: Sendable {

    // MARK: - Row type

    struct IndexRow: FetchableRecord, PersistableRecord, Sendable {
        var entity: String
        var entityId: String
        var title: String
        var body: String
        var tags: String
        var updatedAt: String

        static var databaseTableName: String { "search_index" }

        enum Columns {
            static let entity    = Column("entity")
            static let entityId  = Column("entityId")
            static let title     = Column("title")
            static let body      = Column("body")
            static let tags      = Column("tags")
            static let updatedAt = Column("updatedAt")
        }

        func encode(to container: inout PersistenceContainer) throws {
            container["entity"]    = entity
            container["entityId"]  = entityId
            container["title"]     = title
            container["body"]      = body
            container["tags"]      = tags
            container["updatedAt"] = updatedAt
        }

        /// Memberwise init for constructing rows to insert.
        init(entity: String, entityId: String, title: String, body: String, tags: String, updatedAt: String) {
            self.entity    = entity
            self.entityId  = entityId
            self.title     = title
            self.body      = body
            self.tags      = tags
            self.updatedAt = updatedAt
        }

        /// GRDB `FetchableRecord` init from a database row.
        init(row: Row) {
            entity    = row["entity"]
            entityId  = row["entityId"]
            title     = row["title"]
            body      = row["body"]
            tags      = row["tags"]
            updatedAt = row["updatedAt"]
        }
    }

    // MARK: - Properties

    private let db: any DatabaseWriter

    // MARK: - Init

    init(db: any DatabaseWriter) {
        self.db = db
    }

    // MARK: - Upsert

    /// Insert or replace a row. FTS5 tables don't support ON CONFLICT;
    /// we delete first, then insert to achieve upsert semantics.
    func upsert(_ row: IndexRow) throws {
        try db.write { database in
            try database.execute(
                sql: "DELETE FROM search_index WHERE entity = ? AND entityId = ?",
                arguments: [row.entity, row.entityId]
            )
            try database.execute(
                sql: """
                INSERT INTO search_index(entity, entityId, title, body, tags, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [row.entity, row.entityId, row.title, row.body, row.tags, row.updatedAt]
            )
        }
    }

    // MARK: - Delete

    func delete(entity: String, entityId: String) throws {
        try db.write { database in
            try database.execute(
                sql: "DELETE FROM search_index WHERE entity = ? AND entityId = ?",
                arguments: [entity, entityId]
            )
        }
    }

    // MARK: - Search

    struct RawHit: Sendable {
        let entity: String
        let entityId: String
        let title: String
        let snippet: String
        let rank: Double
    }

    /// Returns raw hits sorted by BM25 rank (ascending = more relevant).
    func search(query: String, entityFilter: String?, limit: Int) throws -> [RawHit] {
        try db.read { database in
            let escaped = Self.escapeFTSQuery(query)
            guard !escaped.isEmpty else { return [] }

            let entityClause: String
            let args: StatementArguments
            if let filter = entityFilter {
                entityClause = "AND entity = ?"
                args = [escaped, filter, limit]
            } else {
                entityClause = ""
                args = [escaped, limit]
            }

            let sql = """
            SELECT entity, entityId, title,
                   snippet(search_index, 2, '<b>', '</b>', '…', 10) AS snippet,
                   rank
            FROM search_index
            WHERE search_index MATCH ?
            \(entityClause)
            ORDER BY rank
            LIMIT ?
            """

            return try Row.fetchAll(database, sql: sql, arguments: args).map { row in
                RawHit(
                    entity:  row["entity"],
                    entityId: row["entityId"],
                    title:   row["title"],
                    snippet: row["snippet"],
                    rank:    row["rank"]
                )
            }
        }
    }

    // MARK: - FTS query escaping

    /// Converts a raw user query into a safe FTS5 MATCH expression.
    /// Appends `*` for prefix matching on the last token.
    static func escapeFTSQuery(_ raw: String) -> String {
        let tokens = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { token -> String in
                // Escape FTS5 special characters inside a phrase
                let safe = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(safe)\""
            }
        guard !tokens.isEmpty else { return "" }
        // Prefix the last token so typing "iph" also matches "iphone"
        var result = tokens
        if var last = result.last {
            last = String(last.dropLast()) + "*\""  // replace closing " with *"
            result[result.count - 1] = last
        }
        return result.joined(separator: " ")
    }
}
