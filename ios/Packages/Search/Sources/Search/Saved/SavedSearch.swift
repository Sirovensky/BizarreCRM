import Foundation

/// §18.5 — A persisted named search with optional entity scope.
public struct SavedSearch: Identifiable, Hashable, Codable, Sendable {
    public let id: String           // UUID string
    public var name: String
    public var query: String
    public var entity: EntityFilter
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        query: String,
        entity: EntityFilter = .all,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.entity = entity
        self.createdAt = createdAt
    }
}
