import Foundation
import Core

// MARK: - FeatureFlagManager

/// Resolves feature flag values using a three-tier precedence:
///
/// 1. Local override (stored in `UserDefaults`) — developer/QA use only.
/// 2. Server value (provided at login / flag fetch via `updateServerValues`).
/// 3. `FeatureFlag.defaultValue` — compile-time conservative default.
///
/// Conforms to the "Keychain for secrets" rule: feature flags are not secrets,
/// so `UserDefaults` is appropriate for local overrides.
@MainActor
public final class FeatureFlagManager: Sendable {

    // MARK: - Singleton

    public static let shared = FeatureFlagManager()

    // MARK: - Storage

    private let defaults: UserDefaults
    private let overrideKeyPrefix = "ffOverride_"
    private let serverKeyPrefix   = "ffServer_"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Designated initializer for testing — use an ephemeral UserDefaults suite.
    ///
    /// ```swift
    /// let sut = FeatureFlagManager(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    /// ```
    public init(testDefaults defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Returns the effective boolean value for `flag`:
    /// local override → server value → compile-time default.
    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        if let local = localOverride(for: flag) {
            return local
        }
        if let server = serverValue(for: flag) {
            return server
        }
        return flag.defaultValue
    }

    /// Sets a local override for `flag`.
    /// Pass `nil` to remove the override and fall back to the server / default.
    public func setLocalOverride(_ flag: FeatureFlag, enabled: Bool?) {
        let key = overrideKeyPrefix + flag.rawValue
        if let enabled {
            defaults.set(enabled, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Removes all local overrides.
    public func clearAllOverrides() {
        for flag in FeatureFlag.allCases {
            defaults.removeObject(forKey: overrideKeyPrefix + flag.rawValue)
        }
    }

    /// Updates the cached server-side value for a flag.
    /// Call this after fetching `/feature-flags` from the server.
    public func updateServerValue(_ flag: FeatureFlag, enabled: Bool) {
        defaults.set(enabled, forKey: serverKeyPrefix + flag.rawValue)
    }

    /// Bulk-update from a server response dictionary (`rawValue → Bool`).
    public func updateServerValues(_ dict: [String: Bool]) {
        for flag in FeatureFlag.allCases {
            if let value = dict[flag.rawValue] {
                updateServerValue(flag, enabled: value)
            }
        }
    }

    /// Returns whether a local override is currently set (and its value).
    public func localOverride(for flag: FeatureFlag) -> Bool? {
        let key = overrideKeyPrefix + flag.rawValue
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    /// Returns the last-cached server value if one has been received.
    public func serverValue(for flag: FeatureFlag) -> Bool? {
        let key = serverKeyPrefix + flag.rawValue
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    /// `true` if a local override exists for `flag`.
    public func hasLocalOverride(for flag: FeatureFlag) -> Bool {
        localOverride(for: flag) != nil
    }
}
