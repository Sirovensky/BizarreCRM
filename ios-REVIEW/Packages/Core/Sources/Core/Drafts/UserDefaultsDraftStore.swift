import Foundation

// §20 Draft Recovery — UserDefaultsDraftStore
// DraftStoreProtocol implementation backed by a suite-scoped UserDefaults.
//
// Phase-0 design notes:
//  - Payload and metadata are stored as separate Data blobs so that
//    `listPending()` can decode metadata without decoding (potentially large)
//    payload bytes.
//  - An in-memory index (stored in UserDefaults under `indexKey`) tracks which
//    keys are in use, avoiding a full scan on every read.
//  - Date encoding uses secondsSince1970 for sub-second fidelity (iso8601
//    rounds to the nearest second, which breaks ordering tests that save two
//    drafts < 1 s apart).
//
// TODO(Phase 2): Swap for a GRDB-backed store — the API is identical so
//               feature owners just inject a different concrete type.

/// UserDefaults-backed implementation of `DraftStoreProtocol`.
///
/// Each instance is isolated to a named UserDefaults suite, which makes it
/// trivial to inject a throwaway suite in unit tests:
/// ```swift
/// let store = UserDefaultsDraftStore(suiteName: "test.\(UUID().uuidString)")
/// ```
///
/// For production use, omit `suiteName` (defaults to `nil` → `.standard`).
public actor UserDefaultsDraftStore: DraftStoreProtocol {

    // MARK: — Storage keys

    private static let payloadPrefix = "com.bizarrecrm.draft.payload."
    private static let metaPrefix    = "com.bizarrecrm.draft.meta."
    private static let indexKey      = "com.bizarrecrm.draft.index"

    // MARK: — Dependencies

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: — Init

    /// - Parameter suiteName: UserDefaults suite. Pass `nil` to use `.standard`.
    public init(suiteName: String? = nil) {
        self.defaults = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        self.decoder = dec
    }

    // MARK: — DraftStoreProtocol

    public func save<T: Codable & Sendable>(_ draft: T, forKey key: DraftKey) async throws {
        let payloadData = try encoder.encode(draft)
        let record = DraftRecord(
            screen: key.entityKind,
            entityId: key.id,
            updatedAt: Date(),
            bytes: payloadData.count
        )
        let metaData = try encoder.encode(record)

        defaults.set(payloadData, forKey: payloadStorageKey(key))
        defaults.set(metaData,    forKey: metaStorageKey(key))
        addToIndex(key.storageKey)
    }

    public func load<T: Codable & Sendable>(_ type: T.Type, forKey key: DraftKey) async throws -> T? {
        guard let data = defaults.data(forKey: payloadStorageKey(key)) else { return nil }
        return try decoder.decode(type, from: data)
    }

    public func delete(forKey key: DraftKey) async {
        defaults.removeObject(forKey: payloadStorageKey(key))
        defaults.removeObject(forKey: metaStorageKey(key))
        removeFromIndex(key.storageKey)
    }

    public func listPending() async -> [DraftRecord] {
        currentIndex()
            .compactMap { storageKey -> DraftRecord? in
                guard let data = defaults.data(forKey: Self.metaPrefix + storageKey) else { return nil }
                return try? decoder.decode(DraftRecord.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func prune(olderThan interval: TimeInterval) async {
        let cutoff = Date().addingTimeInterval(-interval)
        let staleKeys = currentIndex().filter { storageKey -> Bool in
            guard let data = defaults.data(forKey: Self.metaPrefix + storageKey),
                  let record = try? decoder.decode(DraftRecord.self, from: data)
            else { return true } // corrupt entry — remove
            return record.updatedAt < cutoff
        }
        for storageKey in staleKeys {
            defaults.removeObject(forKey: Self.payloadPrefix + storageKey)
            defaults.removeObject(forKey: Self.metaPrefix + storageKey)
            removeFromIndex(storageKey)
        }
    }

    // MARK: — Private helpers

    private func payloadStorageKey(_ key: DraftKey) -> String {
        Self.payloadPrefix + key.storageKey
    }

    private func metaStorageKey(_ key: DraftKey) -> String {
        Self.metaPrefix + key.storageKey
    }

    private func currentIndex() -> [String] {
        defaults.stringArray(forKey: Self.indexKey) ?? []
    }

    private func addToIndex(_ entry: String) {
        var idx = currentIndex()
        if !idx.contains(entry) { idx.append(entry) }
        defaults.set(idx, forKey: Self.indexKey)
    }

    private func removeFromIndex(_ entry: String) {
        var idx = currentIndex()
        idx.removeAll { $0 == entry }
        defaults.set(idx, forKey: Self.indexKey)
    }
}
