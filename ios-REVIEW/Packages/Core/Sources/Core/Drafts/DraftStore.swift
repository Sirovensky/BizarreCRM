import Foundation

// §63 Draft recovery — DraftStore
// Phase 0 foundation
//
// MVP: UserDefaults-backed.
// TODO(Phase 2): Migrate to GRDB for crash-durability — GRDB survives force-quit
//               whereas UserDefaults may not be flushed.  The public API is
//               identical so the migration is transparent to callers.

/// Thread-safe store for in-progress form drafts.
///
/// Keyed by `(screen, entityId?)`.  Drafts older than `pruneThreshold`
/// (default 30 days) are discarded automatically on next `prune()`.
public actor DraftStore {

    // MARK: — Configuration

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // UserDefaults key prefix
    private static let payloadPrefix = "com.bizarrecrm.draft.payload."
    private static let metaPrefix    = "com.bizarrecrm.draft.meta."
    private static let indexKey      = "com.bizarrecrm.draft.index"

    // MARK: — Init

    /// - Parameter suiteName: UserDefaults suite name. Pass `nil` for `.standard`.
    ///   Inject a unique string in tests for isolation.
    public init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.encoder = JSONEncoder()
        // Use secondsSince1970 for full sub-second precision; iso8601 rounds to seconds.
        self.encoder.dateEncodingStrategy = .secondsSince1970
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }

    // MARK: — Public API

    /// Persist `draft` for the given screen / entity.
    public func save<T: Codable & Sendable>(
        _ draft: T,
        screen: String,
        entityId: String?
    ) async throws {
        let data = try encoder.encode(draft)
        let key = DraftRecord.makeId(screen: screen, entityId: entityId)
        let record = DraftRecord(
            screen: screen,
            entityId: entityId,
            updatedAt: Date(),
            bytes: data.count
        )
        let metaData = try encoder.encode(record)

        defaults.set(data,     forKey: Self.payloadPrefix + key)
        defaults.set(metaData, forKey: Self.metaPrefix    + key)
        addToIndex(key: key)
    }

    /// Load a previously saved draft, or return `nil` if none exists.
    public func load<T: Codable & Sendable>(
        _ type: T.Type,
        screen: String,
        entityId: String?
    ) async throws -> T? {
        let key = DraftRecord.makeId(screen: screen, entityId: entityId)
        guard let data = defaults.data(forKey: Self.payloadPrefix + key) else { return nil }
        return try decoder.decode(type, from: data)
    }

    /// Remove the draft for a specific screen / entity (e.g. after successful save).
    public func clear(screen: String, entityId: String?) async {
        let key = DraftRecord.makeId(screen: screen, entityId: entityId)
        defaults.removeObject(forKey: Self.payloadPrefix + key)
        defaults.removeObject(forKey: Self.metaPrefix    + key)
        removeFromIndex(key: key)
    }

    /// Return metadata for all stored drafts (for the "recover" list).
    public func allDrafts() async -> [DraftRecord] {
        index().compactMap { key -> DraftRecord? in
            guard let data = defaults.data(forKey: Self.metaPrefix + key) else { return nil }
            return try? decoder.decode(DraftRecord.self, from: data)
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Delete drafts whose `updatedAt` is older than `olderThan` seconds ago.
    /// Defaults to 30 days.
    public func prune(olderThan interval: TimeInterval = 30 * 86_400) async {
        let cutoff = Date().addingTimeInterval(-interval)
        let staleKeys = index().filter { key -> Bool in
            guard let data = defaults.data(forKey: Self.metaPrefix + key),
                  let record = try? decoder.decode(DraftRecord.self, from: data)
            else { return true } // corrupt — remove
            return record.updatedAt < cutoff
        }
        for key in staleKeys {
            defaults.removeObject(forKey: Self.payloadPrefix + key)
            defaults.removeObject(forKey: Self.metaPrefix    + key)
            removeFromIndex(key: key)
        }
    }

    // MARK: — Private index management

    private func index() -> [String] {
        defaults.stringArray(forKey: Self.indexKey) ?? []
    }

    private func addToIndex(key: String) {
        var idx = index()
        if !idx.contains(key) { idx.append(key) }
        defaults.set(idx, forKey: Self.indexKey)
    }

    private func removeFromIndex(key: String) {
        var idx = index()
        idx.removeAll { $0 == key }
        defaults.set(idx, forKey: Self.indexKey)
    }
}
