import Foundation
import Persistence

// MARK: - §79 Recent servers store

/// Stores the last N server URLs the user has logged into, for quick-pick
/// chips on the login screen.
///
/// Stored in UserDefaults (non-sensitive — only host names, not credentials).
/// Max 5 entries, newest first.
///
/// **Thread-safety:** actor-isolated.
public actor RecentServersStore {

    // MARK: - Singleton

    public static let shared = RecentServersStore()

    // MARK: - Constants

    public static let maxCount: Int = 5
    private static let defaultsKey = "auth.recentServers"

    // MARK: - State (loaded once, kept in sync)

    private var entries: [RecentServer]

    // MARK: - Init

    public init() {
        self.entries = Self.loadFromDefaults()
    }

    // MARK: - Public API

    /// The current list, newest first.
    public var all: [RecentServer] { entries }

    /// Add or bump `url` to the top of the list. Trims to `maxCount`.
    public func record(url: URL, name: String?) {
        // Remove any existing entry for this host so we don't duplicate.
        entries.removeAll { $0.host == url.host }
        let entry = RecentServer(url: url, displayName: name ?? url.host ?? url.absoluteString, lastUsed: Date())
        entries.insert(entry, at: 0)
        if entries.count > Self.maxCount {
            entries = Array(entries.prefix(Self.maxCount))
        }
        Self.saveToDefaults(entries)
    }

    /// Remove all recent servers (e.g. user explicitly clears history).
    public func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    // MARK: - Persistence

    private static func loadFromDefaults() -> [RecentServer] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([RecentServer].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveToDefaults(_ entries: [RecentServer]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

// MARK: - RecentServer

/// A single recently-used server entry.
public struct RecentServer: Codable, Identifiable, Sendable, Hashable {
    public var id: String { host }
    public let url: URL
    public let displayName: String
    public let lastUsed: Date

    public var host: String { url.host ?? url.absoluteString }

    public init(url: URL, displayName: String, lastUsed: Date) {
        self.url = url
        self.displayName = displayName
        self.lastUsed = lastUsed
    }
}
