import Foundation

// §68.2 — StateRestorer
// Persists and restores the last-selected tab and list row between launches.
// Stored in UserDefaults under the `com.bizarrecrm.state.*` namespace.

// MARK: - StateRestorer

/// Persists and restores basic navigation state: last tab index + last row ID.
///
/// Conforms to `@unchecked Sendable` because all mutations happen on the
/// main actor in practice, and `UserDefaults` is itself thread-safe.
public final class StateRestorer: @unchecked Sendable {

    // MARK: Shared instance

    public static let shared = StateRestorer()

    // MARK: UserDefaults keys

    private enum Keys {
        static let lastTabIndex = "com.bizarrecrm.state.lastTabIndex"
        static let lastRowID    = "com.bizarrecrm.state.lastRowID"
    }

    // MARK: Private

    private let defaults: UserDefaults

    // MARK: Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Tab index

    /// The last active tab index, or `nil` if never persisted.
    public var lastTabIndex: Int? {
        get {
            let raw = defaults.integer(forKey: Keys.lastTabIndex)
            // `integer(forKey:)` returns 0 for missing keys;
            // we use -1 as the "not set" sentinel.
            return defaults.object(forKey: Keys.lastTabIndex) == nil ? nil : raw
        }
        set {
            if let v = newValue {
                defaults.set(v, forKey: Keys.lastTabIndex)
            } else {
                defaults.removeObject(forKey: Keys.lastTabIndex)
            }
        }
    }

    // MARK: - Last row ID

    /// The last selected list row identifier (entity UUID as string), or `nil`.
    public var lastRowID: String? {
        get { defaults.string(forKey: Keys.lastRowID) }
        set {
            if let v = newValue {
                defaults.set(v, forKey: Keys.lastRowID)
            } else {
                defaults.removeObject(forKey: Keys.lastRowID)
            }
        }
    }

    // MARK: - Convenience

    /// Clears all persisted state (e.g. on sign-out).
    public func clear() {
        defaults.removeObject(forKey: Keys.lastTabIndex)
        defaults.removeObject(forKey: Keys.lastRowID)
    }
}
