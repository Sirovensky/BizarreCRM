import Foundation
import Core

/// §18.6 — Actor that persists the last 20 search queries in UserDefaults.
public actor RecentSearchStore {

    // MARK: - Constants

    private static let udKey = "bizarrecrm.recentSearches"
    private static let maxCount = 20

    // MARK: - Private state

    private var queries: [String]

    // MARK: - Init

    public init() {
        self.queries = Self.loadFromDefaults()
    }

    // MARK: - Read

    /// Most-recent first.
    public var all: [String] { queries }

    // MARK: - Write

    /// Prepend `query`. Deduplicates (case-insensitive). Evicts oldest past 20.
    public func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let deduped = queries.filter { $0.lowercased() != trimmed.lowercased() }
        let updated = ([trimmed] + deduped).prefix(Self.maxCount)
        queries = Array(updated)
        persist()
    }

    public func remove(_ query: String) {
        queries.removeAll { $0 == query }
        persist()
    }

    public func clear() {
        queries = []
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(queries, forKey: Self.udKey)
    }

    private static func loadFromDefaults() -> [String] {
        UserDefaults.standard.stringArray(forKey: udKey) ?? []
    }
}
