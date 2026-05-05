import Foundation

// MARK: - CommandPaletteFavoritesStore

/// Persists a set of pinned command IDs in `UserDefaults`.
///
/// Pinned commands appear at the top of the command palette result list.
/// The store is `Sendable` and has no mutable shared state beyond
/// `UserDefaults`, mirroring the pattern used by `RecentUsageStore`.
///
/// ## Usage
/// ```swift
/// let store = CommandPaletteFavoritesStore()
/// store.pin(id: "new-ticket")
/// store.unpin(id: "open-pos")
/// let pinned = store.pinnedIDs   // ["new-ticket"]
/// ```
public final class CommandPaletteFavoritesStore: Sendable {

    // MARK: - Constants

    private let key: String

    /// Default UserDefaults key.
    public static let defaultKey = "com.bizarrecrm.commandpalette.pinnedIDs"

    // MARK: - Init

    public init(userDefaultsKey: String = CommandPaletteFavoritesStore.defaultKey) {
        self.key = userDefaultsKey
    }

    // MARK: - Public API

    /// Ordered list of pinned action IDs (insertion order preserved).
    public var pinnedIDs: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    /// Returns `true` if `id` is currently pinned.
    public func isPinned(id: String) -> Bool {
        pinnedIDs.contains(id)
    }

    /// Pin `id`. No-op if already pinned.
    public func pin(id: String) {
        var ids = pinnedIDs
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// Unpin `id`. No-op if not pinned.
    public func unpin(id: String) {
        var ids = pinnedIDs
        ids.removeAll { $0 == id }
        UserDefaults.standard.set(ids, forKey: key)
    }

    /// Toggle the pinned state of `id`.
    /// - Returns: `true` if the action is now pinned, `false` if unpinned.
    @discardableResult
    public func toggle(id: String) -> Bool {
        if isPinned(id: id) {
            unpin(id: id)
            return false
        } else {
            pin(id: id)
            return true
        }
    }

    /// Resolves pinned IDs to full `CommandAction` values from a catalog.
    ///
    /// IDs that no longer exist in the catalog are silently dropped.
    /// Preserves the pinned insertion order.
    ///
    /// - Parameter catalog: All available actions.
    /// - Returns: Pinned actions in pinned-insertion order.
    public func pinnedActions(from catalog: [CommandAction]) -> [CommandAction] {
        let index = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return pinnedIDs.compactMap { index[$0] }
    }

    // MARK: - Reset (test helper)

    /// Remove all pinned IDs. Exposed for unit tests; do not call in production.
    public func _resetForTesting() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
