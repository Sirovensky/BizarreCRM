import Foundation

/// Persists the last 10 executed action IDs in `UserDefaults`.
/// The most-recently used ID sits at index 0.
public final class RecentUsageStore: Sendable {
    private let key: String
    private let maxCount = 10

    public init(userDefaultsKey: String = "com.bizarrecrm.commandpalette.recentIDs") {
        self.key = userDefaultsKey
    }

    // MARK: - Public API

    /// Ordered list of action IDs, most-recent first.
    public var recentIDs: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Record `id` as the most-recently used action.
    /// Deduplicates and trims to `maxCount`.
    public func record(id: String) {
        var ids = recentIDs
        ids.removeAll { $0 == id }     // deduplicate
        ids.insert(id, at: 0)          // move/insert at front
        if ids.count > maxCount {
            ids = Array(ids.prefix(maxCount))
        }
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// Score boost for `id` based on recency.
    /// Returns 0 if `id` is not in the recent list.
    /// Index 0 (most recent) gets the highest boost.
    public func boost(for id: String) -> Double {
        let ids = recentIDs
        guard let index = ids.firstIndex(of: id) else { return 0 }
        // Linear decay: index 0 → boost 10, index 9 → boost 1
        return Double(maxCount - index)
    }
}
