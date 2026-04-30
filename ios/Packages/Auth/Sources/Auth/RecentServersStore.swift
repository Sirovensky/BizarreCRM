import Foundation
import Persistence
import Networking

// MARK: - RecentServersStore
//
// §79.1 — Login screen remembers recently-used servers in a chip row for
// quick pick. Stores up to 5 server URLs + display names; most-recent first.
// Backed by UserDefaults (not Keychain — these are display-only hints, not secrets).
//
// Integration: call `record(url:name:)` after a successful server probe;
// display via `all` in the server-picker panel.

public struct RecentServer: Codable, Sendable, Identifiable, Equatable {
    public let url: URL
    public let displayName: String?
    public let lastUsedAt: Date

    public var id: URL { url }

    public init(url: URL, displayName: String?, lastUsedAt: Date = Date()) {
        self.url = url
        self.displayName = displayName
        self.lastUsedAt = lastUsedAt
    }

    /// Short label for UI chips — shop subdomain or host.
    public var chipLabel: String {
        if let name = displayName, !name.isEmpty { return name }
        // Strip common cloud subdomain for brevity: "acme.bizarrecrm.com" → "acme"
        let host = url.host ?? url.absoluteString
        if host.hasSuffix(".bizarrecrm.com") {
            return host.replacingOccurrences(of: ".bizarrecrm.com", with: "")
        }
        return host
    }
}

public enum RecentServersStore {
    private static let key = "bz.recent_servers"
    private static let maxCount = 5

    // MARK: - Read

    public static func all() -> [RecentServer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let servers = try? JSONDecoder().decode([RecentServer].self, from: data)
        else { return [] }
        return servers.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    // MARK: - Write

    /// Records a server access. If the URL already exists, updates its
    /// `lastUsedAt` and display name; otherwise prepends it. Trims to `maxCount`.
    public static func record(url: URL, displayName: String?) {
        var current = all().filter { $0.url != url }
        current.insert(RecentServer(url: url, displayName: displayName), at: 0)
        let trimmed = Array(current.prefix(maxCount))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
