import Foundation

// MARK: - CommandPaletteHistoryClearer

/// Wraps a `RecentUsageStore` and provides a `clearHistory()` operation by
/// overwriting the stored list with an empty array.
///
/// This companion type lives in the Extras layer because `RecentUsageStore.key`
/// is file-private; rather than patching the base type, the clearer stores its
/// own reference to the defaults key at construction time.
public struct CommandPaletteHistoryClearer: Sendable {
    private let defaultsKey: String

    /// Creates a clearer bound to the same UserDefaults key as `store`.
    ///
    /// Call `store.recentIDs` to confirm the key before passing it here.
    /// Convenience initialiser with the canonical default key:
    ///
    /// ```swift
    /// let clearer = CommandPaletteHistoryClearer()
    /// ```
    public init(userDefaultsKey: String = "com.bizarrecrm.commandpalette.recentIDs") {
        self.defaultsKey = userDefaultsKey
    }

    /// Removes all stored recent-command IDs.
    public func clearHistory() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
