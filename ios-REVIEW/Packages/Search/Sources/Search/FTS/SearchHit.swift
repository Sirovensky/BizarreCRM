import Foundation

/// §18.3 — One result row returned by `FTSIndexStore.search(...)`.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public let id: String            // "\(entity):\(entityId)"
    public let entity: String
    public let entityId: String
    public let title: String
    public let snippet: String
    public let score: Double         // BM25 rank (lower = more relevant in FTS5)

    public init(
        entity: String,
        entityId: String,
        title: String,
        snippet: String,
        score: Double
    ) {
        self.id = "\(entity):\(entityId)"
        self.entity = entity
        self.entityId = entityId
        self.title = title
        self.snippet = snippet
        self.score = score
    }
}
