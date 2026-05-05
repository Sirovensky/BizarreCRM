import Foundation
import Core

/// §16.14 — Actor-isolated held-cart store. Persists to `UserDefaults`
/// under the key `"pos_held_carts"`. Expired carts (> 24 h) are pruned
/// automatically on every load.
///
/// TODO: migrate backing store to GRDB when Phase 3 lands.
public actor HeldCartStore {
    public static let shared = HeldCartStore()

    private let defaults: UserDefaults
    private let key = "pos_held_carts"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Public API

    /// Return all non-expired held carts, sorted newest-first.
    public func loadAll() -> [HeldCart] {
        let all  = rawLoad()
        let live = all.filter { !$0.isExpired }
        if live.count != all.count {
            rawSave(live)  // prune expired entries
        }
        return live.sorted { $0.savedAt > $1.savedAt }
    }

    /// Persist a new held cart. Replaces any existing entry with the same `id`.
    public func save(_ held: HeldCart) {
        var all = rawLoad()
        all.removeAll { $0.id == held.id }
        all.append(held)
        rawSave(all)
    }

    /// Delete a held cart by id. Silent no-op if not found.
    public func delete(id: UUID) {
        var all = rawLoad()
        all.removeAll { $0.id == id }
        rawSave(all)
    }

    /// Delete all held carts (e.g. after shift close).
    public func deleteAll() {
        defaults.removeObject(forKey: key)
    }

    // MARK: - Private

    private func rawLoad() -> [HeldCart] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try decoder.decode([HeldCart].self, from: data)
        } catch {
            AppLog.pos.error("HeldCartStore.load failed: \(error, privacy: .public)")
            defaults.removeObject(forKey: key)
            return []
        }
    }

    private func rawSave(_ carts: [HeldCart]) {
        do {
            let data = try encoder.encode(carts)
            defaults.set(data, forKey: key)
        } catch {
            AppLog.pos.error("HeldCartStore.save failed: \(error, privacy: .public)")
        }
    }
}
