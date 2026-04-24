import Foundation

/// §18 — Actor that persists saved searches in an App Group UserDefaults suite.
///
/// Sort order: by `lastUsedAt` descending (never-used items fall to the bottom,
/// sorted by `createdAt` descending among themselves).
/// Name uniqueness: attempting to save a search whose normalised name already
/// exists throws `SavedSearchStoreError.duplicateName`.
public actor SavedSearchStore {

    // MARK: - Errors

    public enum SavedSearchStoreError: Error, Equatable {
        case duplicateName(String)
    }

    // MARK: - Constants

    private static let udKey = "bizarrecrm.savedSearches"
    /// App Group suite. Falls back to `.standard` when the suite is unavailable
    /// (e.g. in unit-test targets that don't configure entitlements).
    private static let suiteName = "group.com.bizarrecrm"

    // MARK: - Private state

    private var items: [SavedSearch]
    private let defaults: UserDefaults

    // MARK: - Init

    /// Designated initialiser. Inject a custom `UserDefaults` for testing.
    public init(defaults: UserDefaults? = nil) {
        let ud = defaults
            ?? UserDefaults(suiteName: Self.suiteName)
            ?? UserDefaults.standard
        self.defaults = ud
        self.items = Self.load(from: ud)
    }

    // MARK: - Read

    /// All saved searches, most-recently-used first.
    /// Items never used are sorted by creation date (newest first) after used ones.
    public var all: [SavedSearch] {
        items.sorted { lhs, rhs in
            switch (lhs.lastUsedAt, rhs.lastUsedAt) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return lhs.createdAt > rhs.createdAt
            }
        }
    }

    // MARK: - Write

    /// Persist a new saved search.
    /// - Throws: `SavedSearchStoreError.duplicateName` when a search with the
    ///   same normalised name already exists (case-insensitive, whitespace-trimmed).
    public func save(_ search: SavedSearch) throws {
        let normNew = search.name.trimmingCharacters(in: .whitespaces).lowercased()
        if let conflict = items.first(where: {
            $0.id != search.id &&
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normNew
        }) {
            throw SavedSearchStoreError.duplicateName(conflict.name)
        }
        items.removeAll { $0.id == search.id }
        items.append(search)
        persist()
    }

    /// Mark a search as used right now (updates `lastUsedAt`).
    public func recordUse(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        var updated = items[idx]
        updated = SavedSearch(
            id: updated.id,
            name: updated.name,
            query: updated.query,
            entity: updated.entity,
            createdAt: updated.createdAt,
            lastUsedAt: Date()
        )
        items[idx] = updated
        persist()
    }

    public func delete(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    /// Rename a saved search.
    /// - Throws: `SavedSearchStoreError.duplicateName` when the new name
    ///   conflicts with an existing entry.
    public func rename(id: String, newName: String) throws {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let normNew = newName.trimmingCharacters(in: .whitespaces).lowercased()
        if let conflict = items.first(where: {
            $0.id != id &&
            $0.name.trimmingCharacters(in: .whitespaces).lowercased() == normNew
        }) {
            throw SavedSearchStoreError.duplicateName(conflict.name)
        }
        let old = items[idx]
        items[idx] = SavedSearch(
            id: old.id,
            name: newName.trimmingCharacters(in: .whitespaces),
            query: old.query,
            entity: old.entity,
            createdAt: old.createdAt,
            lastUsedAt: old.lastUsedAt
        )
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.udKey)
    }

    private static func load(from defaults: UserDefaults) -> [SavedSearch] {
        guard
            let data = defaults.data(forKey: udKey),
            let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data)
        else { return [] }
        return decoded
    }
}
