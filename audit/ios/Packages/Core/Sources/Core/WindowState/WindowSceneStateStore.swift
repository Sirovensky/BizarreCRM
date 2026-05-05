import Foundation

// §22.4 Multi-window / Stage Manager — per-window persistence

// MARK: - WindowSceneStateStore

/// `@MainActor` store that persists one `WindowSceneState` per
/// `UISceneSession.persistentIdentifier` in `UserDefaults.standard`.
///
/// Key layout in UserDefaults:
/// ```
/// scene.state.<persistentIdentifier>  →  JSON-encoded WindowSceneState
/// ```
///
/// ## Usage
/// ```swift
/// let store = WindowSceneStateStore()
/// store.save(state, for: session.persistentIdentifier)
/// let restored = store.load(for: session.persistentIdentifier)
/// ```
@MainActor
public final class WindowSceneStateStore {

    // MARK: - Constants

    /// Prefix applied to every key this store writes to `UserDefaults`.
    public static let keyPrefix = "scene.state."

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // MARK: - Init

    /// - Parameter defaults: Defaults store to use; injectable for testing.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Public API

    /// Persists `state` for the given scene session identifier.
    ///
    /// - Parameters:
    ///   - state: The snapshot to store.
    ///   - sessionId: `UISceneSession.persistentIdentifier`.
    public func save(_ state: WindowSceneState, for sessionId: String) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: key(for: sessionId))
    }

    /// Returns the previously stored state for `sessionId`, or `nil` when
    /// no snapshot exists or decoding fails.
    ///
    /// - Parameter sessionId: `UISceneSession.persistentIdentifier`.
    public func load(for sessionId: String) -> WindowSceneState? {
        guard let data = defaults.data(forKey: key(for: sessionId)) else { return nil }
        return try? decoder.decode(WindowSceneState.self, from: data)
    }

    /// Removes the stored state for `sessionId`.
    ///
    /// Call this when a scene session is discarded (
    /// `application(_:didDiscardSceneSessions:)`).
    ///
    /// - Parameter sessionId: `UISceneSession.persistentIdentifier`.
    public func remove(for sessionId: String) {
        defaults.removeObject(forKey: key(for: sessionId))
    }

    /// Removes every scene state managed by this store.
    ///
    /// Useful during sign-out to avoid leaking state across accounts.
    public func removeAll() {
        let prefixedKeys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Self.keyPrefix) }
        prefixedKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - Private helpers

    private func key(for sessionId: String) -> String {
        "\(Self.keyPrefix)\(sessionId)"
    }
}
