import Foundation
import Core

/// §18.5 — UserDefaults-backed store for saved searches. TODO: migrate to GRDB.
public actor SavedSearchStore {

    // MARK: - Constants

    private static let udKey = "bizarrecrm.savedSearches"

    // MARK: - Private state

    private var items: [SavedSearch]

    // MARK: - Init

    public init() {
        self.items = Self.loadFromDefaults()
    }

    // MARK: - Read

    public var all: [SavedSearch] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Write

    public func save(_ search: SavedSearch) {
        items.removeAll { $0.id == search.id }
        items.append(search)
        persist()
    }

    public func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func rename(id: String, newName: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items[idx]
        updated = SavedSearch(
            id: updated.id,
            name: newName,
            query: updated.query,
            entity: updated.entity,
            createdAt: updated.createdAt
        )
        items[idx] = updated
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.udKey)
    }

    private static func loadFromDefaults() -> [SavedSearch] {
        guard
            let data = UserDefaults.standard.data(forKey: udKey),
            let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }
        return decoded
    }
}
