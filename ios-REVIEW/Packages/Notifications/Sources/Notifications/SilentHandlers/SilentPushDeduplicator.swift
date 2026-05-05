import Foundation
import Core

// MARK: - SilentPushDeduplicatorStore

/// Persistence back-end for the deduplication window.
///
/// The default implementation (`UserDefaultsDeduplicatorStore`) persists to
/// `UserDefaults(suiteName: "group.com.bizarrecrm")` so processed IDs survive
/// relaunches within the configured window.  Tests inject a lightweight
/// in-memory store.
public protocol SilentPushDeduplicatorStore: Sendable {
    func load() -> [String: TimeInterval]
    func save(_ table: [String: TimeInterval])
}

// MARK: - UserDefaultsDeduplicatorStore

/// App Group `UserDefaults` backed store.  Thread-safe because `UserDefaults`
/// reads/writes are internally serialised.
public struct UserDefaultsDeduplicatorStore: SilentPushDeduplicatorStore, Sendable {

    private static let key = "com.bizarrecrm.silentpush.dedup"
    private let defaults: UserDefaults

    public init(suiteName: String = "group.com.bizarrecrm") {
        // Falls back to standard defaults if the App Group is not yet configured.
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public func load() -> [String: TimeInterval] {
        (defaults.dictionary(forKey: Self.key) as? [String: TimeInterval]) ?? [:]
    }

    public func save(_ table: [String: TimeInterval]) {
        defaults.set(table, forKey: Self.key)
    }
}

// MARK: - InMemoryDeduplicatorStore

/// Ephemeral store for unit tests.
public final class InMemoryDeduplicatorStore: SilentPushDeduplicatorStore, @unchecked Sendable {
    private var table: [String: TimeInterval] = [:]
    public init() {}
    public func load() -> [String: TimeInterval] { table }
    public func save(_ t: [String: TimeInterval]) { table = t }
}

// MARK: - SilentPushDeduplicator

/// Actor-isolated deduplicator that prevents the same silent push from being
/// processed more than once across relaunches.
///
/// ## Algorithm
///
/// - Each processed `messageId` is stored alongside the `Date.timeIntervalSince1970`
///   at which it was first seen.
/// - On every call to `isDuplicate`, the table is scrubbed to remove entries
///   older than `windowDuration` (default 24 hours). This bounds table size
///   even under high push volume.
/// - The table is persisted to the injected `SilentPushDeduplicatorStore` after
///   every mutation so it survives cold relaunches.
///
/// ## Usage
///
/// ```swift
/// let dedup = SilentPushDeduplicator()
/// if await dedup.isDuplicate(envelope.messageId) {
///     return // already handled
/// }
/// // ... process push ...
/// ```
public actor SilentPushDeduplicator {

    // MARK: - Configuration

    /// How long a processed message ID is remembered. Default: 24 hours.
    public let windowDuration: TimeInterval

    // MARK: - State

    private var table: [String: TimeInterval]   // messageId → processedAt
    private let store: any SilentPushDeduplicatorStore

    // MARK: - Init

    public init(
        windowDuration: TimeInterval = 86_400,
        store: any SilentPushDeduplicatorStore = UserDefaultsDeduplicatorStore()
    ) {
        self.windowDuration = windowDuration
        self.store = store
        self.table = store.load()
    }

    // MARK: - Public API

    /// Returns `true` when `messageId` has been seen within the dedup window.
    ///
    /// Side effects:
    /// - If not a duplicate, records the ID and persists.
    /// - Expired entries are evicted on every call.
    public func isDuplicate(_ messageId: String) -> Bool {
        evictExpired()
        if table[messageId] != nil {
            AppLog.sync.debug(
                "SilentPushDeduplicator: duplicate messageId=\(messageId, privacy: .private)"
            )
            return true
        }
        table[messageId] = Date().timeIntervalSince1970
        store.save(table)
        return false
    }

    /// The number of IDs currently tracked in the dedup window.
    public var trackedCount: Int { table.count }

    /// Remove all tracked IDs (useful in tests / logout).
    public func reset() {
        table = [:]
        store.save(table)
    }

    // MARK: - Private

    private func evictExpired() {
        let cutoff = Date().timeIntervalSince1970 - windowDuration
        let before = table.count
        table = table.filter { $0.value >= cutoff }
        let evicted = before - table.count
        if evicted > 0 {
            store.save(table)
            AppLog.sync.debug("SilentPushDeduplicator: evicted \(evicted) expired entries")
        }
    }
}
